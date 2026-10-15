import AppKit
import SwiftUI

/// 데스크톱 위에 떠 있는 컴패니언 포켓몬 오버레이(옵트인, 설정 → 플로팅 펫).
/// - 드래그: 커스텀 `mouseDragged` (클릭과 충돌하지 않음).
/// - 클릭 → 팝오버, 우클릭 → 메뉴, 호버 → 오늘 사용량 콜아웃.
/// - Limit-alert speech bubbles grow the panel; persisted origin is the *pet*, not the panel.
/// - 에너지: 숨김·슬립 시 호스팅 트리 해제.
@MainActor
final class FloatingPetController: NSObject, NSWindowDelegate {
    private let store: UsageStore
    private let player: PlayerStore
    private let defaults: UserDefaults
    private var panel: NSPanel?
    private var hoverPanel: NSPanel?
    private var displayAwake = true
    private var builtAnimated: Bool?
    /// 마지막으로 처리한 「처음 자리로」 요청. 스토어의 값과 다르면 새 요청이 온 것이다.
    private var seenHomeRequests = 0
    private var powerObserver: NSObjectProtocol?

    static let originXKey = "floatingPetOriginX"
    static let originYKey = "floatingPetOriginY"

    /// Squared movement (pt²) below which a mouse-up counts as a click, not a drag.
    static let clickThresholdSquared: CGFloat = 16  // ~4pt

    /// Vertical space above the sprite for the bubble + VStack spacing (pt).
    /// Sized for two wrapped body lines + title + padding + tail (ja strings).
    static let bubbleHeadroom: CGFloat = 72
    /// Minimum panel width while a bubble is showing.
    static let bubbleMinWidth: CGFloat = 180
    /// Horizontal padding inside the bubble chrome (each side). Content + 2× this = `bubbleMinWidth`.
    static let bubbleHorizontalPadding: CGFloat = 8
    /// Fixed text column — wraps instead of growing past the panel (`bubbleMinWidth` − 16).
    static let bubbleContentWidth: CGFloat = bubbleMinWidth - (bubbleHorizontalPadding * 2)

    private var onOpenPopover: (() -> Void)?
    private var onHide: (() -> Void)?

    init(store: UsageStore, player: PlayerStore, defaults: UserDefaults = .standard,
         onOpenPopover: (() -> Void)? = nil, onHide: (() -> Void)? = nil) {
        self.store = store
        self.player = player
        self.defaults = defaults
        self.onOpenPopover = onOpenPopover
        self.onHide = onHide
        super.init()
        observeSettings()
        observePowerState()
        sync()
    }

    static func isClick(from start: NSPoint, to end: NSPoint,
                        thresholdSquared: CGFloat = clickThresholdSquared) -> Bool {
        let dx = end.x - start.x, dy = end.y - start.y
        return dx * dx + dy * dy < thresholdSquared
    }

    func setDisplayAwake(_ awake: Bool) {
        displayAwake = awake
        sync()
    }

    private func observeSettings() {
        withObservationTracking {
            _ = store.floatingPetEnabled
            _ = store.floatingPetSize
            _ = store.floatingPetHomeRequests
            _ = store.currentBubbleAlert
            _ = store.todayTotalTokens
            _ = store.highestLimitUtilization
            _ = store.limitDisplayMode   // hover 툴팁 %의 파생 원천 — 수동 관찰 표면은 직접 추적
            _ = player.language
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.sync()
                self.observeSettings()
            }
        }
    }

    private func observePowerState() {
        powerObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.sync() }
        }
    }

    static func shouldAnimate(lowPower: Bool) -> Bool { !lowPower }

    /// Panel size for a given pet size and bubble visibility. Pure — tested without AppKit layout.
    static func panelSize(petSize: CGFloat, showingBubble: Bool) -> NSSize {
        if showingBubble {
            return NSSize(width: max(petSize, bubbleMinWidth),
                          height: petSize + bubbleHeadroom)
        }
        return NSSize(width: petSize, height: petSize)
    }

    static func panelOrigin(petOrigin: NSPoint, petSize: CGFloat, panelSize: NSSize) -> NSPoint {
        let xInset = max(0, (panelSize.width - petSize) / 2)
        return NSPoint(x: petOrigin.x - xInset, y: petOrigin.y)
    }

    static func petOrigin(panelOrigin: NSPoint, petSize: CGFloat, panelSize: NSSize) -> NSPoint {
        let xInset = max(0, (panelSize.width - petSize) / 2)
        return NSPoint(x: panelOrigin.x + xInset, y: panelOrigin.y)
    }

    /// Measure speech-bubble chrome for a title/body at the fixed content width (wrapping).
    /// Pure AppKit typography — keeps the layout test free of SwiftUI hosting.
    static func measureSpeechBubble(title: String, body: String,
                                    contentWidth: CGFloat = bubbleContentWidth) -> NSSize {
        let titleFont = NSFont.systemFont(ofSize: 11, weight: .bold)
        let bodyFont = NSFont.systemFont(ofSize: 10)
        let constraint = NSSize(width: contentWidth, height: 10_000)
        let opts: NSString.DrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]
        let titleRect = (title as NSString).boundingRect(
            with: constraint, options: opts, attributes: [.font: titleFont])
        let bodyRect = (body as NSString).boundingRect(
            with: constraint, options: opts, attributes: [.font: bodyFont])
        let textWidth = min(contentWidth, max(titleRect.width, bodyRect.width))
        let textHeight = ceil(titleRect.height) + 2 + ceil(bodyRect.height)
        // Match SpeechBubbleView: horizontal padding ×2, vertical 6, bottom pad 6 for the tail.
        let hPad = bubbleHorizontalPadding * 2
        return NSSize(width: textWidth + hPad, height: textHeight + 12 + 6)
    }

    private func sync() {
        // **숨김 분기보다 먼저 처리한다.** 펫이 꺼져 있을 때 눌러도 위치가 지워져야, 다시 켤 때
        // 제자리로 온다. 뒤에 두면 꺼진 상태의 요청이 그냥 버려진다.
        if store.floatingPetHomeRequests != seenHomeRequests {
            seenHomeRequests = store.floatingPetHomeRequests
            Self.clearSavedOrigin(in: defaults)
        }
        guard store.floatingPetEnabled, displayAwake else { hide(); return }
        show()
    }

    /// 저장된 위치를 지운다 — 다음 배치가 `defaultPetOrigin` 으로 떨어진다. **두 축을 함께**
    /// 지운다: 하나만 남으면 그 축의 옛 값과 다른 축의 기본값이 섞인 엉뚱한 자리로 간다.
    static func clearSavedOrigin(in defaults: UserDefaults) {
        defaults.removeObject(forKey: originXKey)
        defaults.removeObject(forKey: originYKey)
    }

    private func show() {
        let p = panel ?? makePanel()
        panel = p
        let wantAnimated = Self.shouldAnimate(lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled)
        if p.contentView == nil || builtAnimated != wantAnimated {
            let hosting = PetHostingView(rootView: AnyView(
                FloatingPetView(animated: wantAnimated)
                    .environment(store).environment(player)))
            hosting.onOpenPopover = onOpenPopover
            // 맞으면 깨지는 아이를 데리고 다닐 때만 연타를 센다. 다른 포켓몬이면 이 경로가
            // 통째로 꺼져 팝오버 여는 속도가 지금 그대로다.
            hosting.breakableProvider = { [weak self] in
                BrokenForm.breaks(speciesID: self?.player.state.partner?.speciesID)
            }
            hosting.onTapped = { [weak self] in self?.player.breakPartnerForm() }
            hosting.onHide = onHide
            hosting.languageProvider = { [weak self] in self?.player.language ?? .systemDefault }
            hosting.onHoverChange = { [weak self] hovering in
                if hovering { self?.showHoverCallout() } else { self?.hideHoverCallout() }
            }
            p.contentView = hosting
            builtAnimated = wantAnimated
        }
        if let hosting = p.contentView as? PetHostingView {
            hosting.toolTip = currentHoverText()
        }
        let petSize = CGFloat(store.floatingPetSize)
        p.setFrame(targetFrame(petSize: petSize, showingBubble: store.currentBubbleAlert != nil),
                   display: true)
        p.orderFrontRegardless()
        if hoverPanel?.isVisible == true { showHoverCallout() }
    }

    private func hide() {
        hideHoverCallout()
        guard let p = panel else { return }
        p.orderOut(nil)
        p.contentView = nil
        builtAnimated = nil
    }

    private func currentHoverText() -> String {
        FloatingPetView.hoverTooltip(
            todayTokens: store.todayTotalTokens,
            limitUtilization: store.highestLimitUtilization,
            mode: store.limitDisplayMode,
            l: L(player.language))
    }

    private func showHoverCallout() {
        guard let pet = panel, pet.isVisible else { return }
        // Don't cover an active limit bubble — the speech bubble is the priority surface.
        if store.currentBubbleAlert != nil { hideHoverCallout(); return }
        let text = currentHoverText()
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .labelColor
        label.backgroundColor = .clear
        label.drawsBackground = false
        label.sizeToFit()

        let pad: CGFloat = 8
        let size = NSSize(width: label.bounds.width + pad * 2,
                          height: label.bounds.height + pad * 2)
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        container.layer?.cornerRadius = 8
        container.layer?.borderWidth = 0.5
        container.layer?.borderColor = NSColor.separatorColor.cgColor
        label.frame.origin = NSPoint(x: pad, y: pad)
        container.addSubview(label)

        let hp = hoverPanel ?? makeHoverPanel()
        hoverPanel = hp
        hp.contentView = container
        hp.setContentSize(size)
        let petFrame = pet.frame
        hp.setFrameOrigin(NSPoint(x: petFrame.midX - size.width / 2, y: petFrame.maxY + 6))
        hp.orderFrontRegardless()
    }

    private func hideHoverCallout() {
        hoverPanel?.orderOut(nil)
        hoverPanel?.contentView = nil
    }

    private func makeHoverPanel() -> NSPanel {
        let p = NSPanel(contentRect: .zero,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.ignoresMouseEvents = true
        p.animationBehavior = .none
        return p
    }

    private func targetFrame(petSize: CGFloat, showingBubble: Bool) -> NSRect {
        let size = Self.panelSize(petSize: petSize, showingBubble: showingBubble)
        let petOrigin: NSPoint
        if let x = defaults.object(forKey: Self.originXKey) as? Double,
           let y = defaults.object(forKey: Self.originYKey) as? Double {
            petOrigin = NSPoint(x: x, y: y)
        } else {
            petOrigin = Self.defaultPetOrigin(petSize: petSize)
        }
        // **패널이 아니라 펫을 본다.** 말풍선이 뜨면 패널이 펫보다 커서, 펫은 화면 밖인데
        // 말풍선 자리만 걸쳐도 예전 가드는 통과시켰다.
        let petRect = NSRect(origin: petOrigin, size: NSSize(width: petSize, height: petSize))
        let reachable = Self.isReachable(petRect, visibleFrames: NSScreen.screens.map(\.visibleFrame))
        let placed = reachable ? petOrigin : Self.defaultPetOrigin(petSize: petSize)
        return NSRect(origin: Self.panelOrigin(petOrigin: placed, petSize: petSize, panelSize: size),
                      size: size)
    }

    /// 이 자리의 펫을 **손으로 잡을 수 있나.** 중심이 어느 화면의 보이는 영역 안에 있으면 그렇다.
    ///
    /// 예전 가드는 "화면과 1pt 라도 겹치면 통과"였다. 그래서 가장자리에 한 줄만 걸친 자리가
    /// 켤 때마다 그대로 복원됐고, 위치는 `UserDefaults` 라 재설치로도 안 지워져 **펫이 영원히
    /// 사라졌다**(사용자 제보: 껐다 켜도·재설치해도 안 돌아온다). 완전히 화면 밖이면 오히려 가드가
    /// 잡아 기본 자리로 돌렸으니, 조금 걸친 경우만 갇힌 것이다.
    ///
    /// 중심을 기준으로 한 이유: 구석에 반쯤 걸쳐 둔 자리는 사용자가 일부러 고른 것이라 살려야 하고,
    /// 중심이 화면 안이면 펫의 최소 4분의 1은 보여 잡을 수 있다. 크기가 0 이면 어디에 있든
    /// 안 보이므로 걸러진다 — 같은 증상을 내는 다른 구멍이다.
    nonisolated static func isReachable(_ pet: NSRect, visibleFrames: [NSRect]) -> Bool {
        guard pet.width > 0, pet.height > 0 else { return false }
        let center = NSPoint(x: pet.midX, y: pet.midY)
        return visibleFrames.contains { $0.contains(center) }
    }

    private static func defaultPetOrigin(petSize: CGFloat) -> NSPoint {
        guard let visible = NSScreen.main?.visibleFrame else { return NSPoint(x: 120, y: 120) }
        return defaultPetOrigin(petSize: petSize, visibleFrame: visible)
    }

    /// 처음 자리 — 화면 오른쪽 아래, 가장자리에서 24pt 안쪽. 「처음 자리로」 버튼과 손에 안 닿는
    /// 자리의 대체값이 **같은 이 값**을 쓴다.
    nonisolated static func defaultPetOrigin(petSize: CGFloat, visibleFrame visible: NSRect) -> NSPoint {
        NSPoint(x: visible.maxX - petSize - 24, y: visible.minY + 24)
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isMovableByWindowBackground = false
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.becomesKeyOnlyIfNeeded = true
        p.allowsToolTipsWhenApplicationIsInactive = true
        p.animationBehavior = .none
        p.delegate = self
        return p
    }

    func windowDidMove(_ notification: Notification) {
        guard let p = panel, p.isVisible else { return }
        let petSize = CGFloat(store.floatingPetSize)
        let size = Self.panelSize(petSize: petSize, showingBubble: store.currentBubbleAlert != nil)
        let pet = Self.petOrigin(panelOrigin: p.frame.origin, petSize: petSize, panelSize: size)
        defaults.set(Double(pet.x), forKey: Self.originXKey)
        defaults.set(Double(pet.y), forKey: Self.originYKey)
        if hoverPanel?.isVisible == true { showHoverCallout() }
    }
}

final class PetHostingView: NSHostingView<AnyView> {
    var onOpenPopover: (() -> Void)?
    /// 지금 파트너가 두드려서 깨질 수 있는 아이인가.
    var breakableProvider: (() -> Bool)?
    /// 연타가 문턱을 넘었을 때.
    var onTapped: (() -> Void)?
    /// 미뤄 둔 팝오버 열기 — 연타가 이어지면 취소한다.
    private var pendingOpen: DispatchWorkItem?
    var onHide: (() -> Void)?
    var onHoverChange: ((Bool) -> Void)?
    var languageProvider: () -> AppLanguage = { .systemDefault }

    private var mouseDownScreen: NSPoint?
    private var originAtDown: NSPoint?
    private var didDrag = false

    override var mouseDownCanMoveWindow: Bool { false }

    static func isClick(from start: NSPoint, to end: NSPoint,
                        thresholdSquared: CGFloat = FloatingPetController.clickThresholdSquared) -> Bool {
        FloatingPetController.isClick(from: start, to: end, thresholdSquared: thresholdSquared)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { onHoverChange?(true) }
    override func mouseExited(with event: NSEvent) { onHoverChange?(false) }

    override func mouseDown(with event: NSEvent) {
        pendingOpen?.cancel()   // 다음 클릭이 왔다 — 미뤄 둔 열기는 취소한다
        if event.modifierFlags.contains(.control) {
            showContextMenu(event)
            return
        }
        mouseDownScreen = NSEvent.mouseLocation
        originAtDown = window?.frame.origin
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, let start = mouseDownScreen, let origin = originAtDown else { return }
        let now = NSEvent.mouseLocation
        if !Self.isClick(from: start, to: now) { didDrag = true }
        window.setFrameOrigin(NSPoint(x: origin.x + (now.x - start.x),
                                      y: origin.y + (now.y - start.y)))
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            mouseDownScreen = nil
            originAtDown = nil
            didDrag = false
        }
        guard !didDrag, let start = mouseDownScreen else { return }
        guard Self.isClick(from: start, to: NSEvent.mouseLocation) else { return }

        // 깨질 수 있는 아이가 아니면 예전 그대로 — 즉시 연다.
        guard breakableProvider?() == true else { onOpenPopover?(); return }

        // **팝오버를 바로 열면 안 된다.** 열리는 순간 다음 클릭이 펫에 안 닿아 연타를 셀 수 없다.
        // 그래서 더블클릭 간격만큼 미뤄 두고, 그 사이에 다음 클릭이 오면 취소한다.
        // 연타 판정은 `clickCount` 로 한다 — OS 가 이미 세고 있는 값이라 내가 타이밍을 만들 필요가 없다.
        pendingOpen?.cancel()
        if event.clickCount >= BrokenForm.tapsToBreak {
            pendingOpen = nil
            onTapped?()
            return
        }
        let open = DispatchWorkItem { [weak self] in self?.onOpenPopover?() }
        pendingOpen = open
        DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval, execute: open)
    }

    override func rightMouseDown(with event: NSEvent) {
        showContextMenu(event)
    }

    private func showContextMenu(_ event: NSEvent) {
        onHoverChange?(false)
        NSApp.activate(ignoringOtherApps: true)
        let l = L(languageProvider())
        let menu = NSMenu(title: "")
        menu.autoenablesItems = false
        let open = menu.addItem(withTitle: l.floatingPetMenuOpen,
                                action: #selector(handleOpen(_:)), keyEquivalent: "")
        open.target = self
        open.isEnabled = true
        let hide = menu.addItem(withTitle: l.floatingPetMenuHide,
                                action: #selector(handleHide(_:)), keyEquivalent: "")
        hide.target = self
        hide.isEnabled = true
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc func handleOpen(_ sender: Any?) { onOpenPopover?() }
    @objc func handleHide(_ sender: Any?) { onHide?() }
}

struct FloatingPetView: View {
    /// 펫은 GIF 원본 속도로 움직인다. 예전엔 0.4s(≈2.5fps) 캡을 걸어 idle wakeup 을 줄였지만,
    /// 그 속도로는 눈에 띄게 굼떠 보여서 캡을 뺐다(사용자 결정, 2026-08-06). 배터리 방어는
    /// 남은 두 가지가 맡는다 — 저전력 모드 정적화(`shouldAnimate`), 숨김/슬립 시 `contentView=nil`.
    static let frameFloor: TimeInterval = 0
    var animated: Bool = true
    @Environment(UsageStore.self) private var store
    @Environment(PlayerStore.self) private var player

    var body: some View {
        let size = CGFloat(store.floatingPetSize)
        VStack(spacing: 8) {
            if let alert = store.currentBubbleAlert {
                SpeechBubbleView(alert: alert, l: L(player.language))
                    .transition(.scale(scale: 0.8, anchor: .bottom).combined(with: .opacity))
                    .zIndex(1)
            }

            SpriteView(speciesID: player.displayedSpeciesID, form: player.displayedForm,
                       size: size, animated: animated,
                       shiny: player.displayedIsShiny, minFrameDelay: Self.frameFloor,
                       speed: Self.speed(store),
                       antialias: store.antialiasSprites)
                .frame(width: size, height: size)
                .zIndex(0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .animation(animated ? .spring(response: 0.3, dampingFraction: 0.7) : nil,
                   value: store.currentBubbleAlert)
    }

    /// 지금 걸릴 배속. 스토어에서 값을 꺼내는 곳이 여기 한 곳뿐이라, 배선이 끊기면
    /// (예: 설정 토글을 안 보고 늘 가속) 테스트가 이 함수 하나로 잡는다.
    static func speed(_ store: UsageStore) -> Double {
        PetSpeed.multiplier(tokensPerMinute: store.recentBurnPerMinute,
                            enabled: store.floatingPetBurnSpeed)
    }

    static func hoverTooltip(todayTokens: Int, limitUtilization: Double?,
                             mode: UsageStore.LimitDisplayMode, l: L) -> String {
        let usage = TokenFormatter.grouped(todayTokens)
        if let pct = limitUtilization {
            let text = TokenFormatter.percent(UsageStore.displayPercent(pct, mode: mode))
            return l.floatingPetHoverWithLimit(usage, mode == .remaining ? l.percentRemaining(text) : text)
        }
        return l.floatingPetHoverTokensOnly(usage)
    }
}

/// Transient limit-alert bubble. Width is capped so ko/en/ja wrap instead of clipping the panel.
private struct SpeechBubbleView: View {
    let alert: UsageStore.LimitAlert
    let l: L

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(alert.isCritical ? l.notifCritical : l.notifWarning)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(alert.isCritical ? .red : .primary)
            Text(l.notifBody(alert.window, TokenFormatter.percent(alert.utilization)))
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: FloatingPetController.bubbleContentWidth, alignment: .leading)
        .padding(.horizontal, FloatingPetController.bubbleHorizontalPadding)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        )
        .overlay(
            Path { path in
                path.move(to: CGPoint(x: 10, y: 0))
                path.addLine(to: CGPoint(x: 20, y: 0))
                path.addLine(to: CGPoint(x: 15, y: 6))
                path.closeSubpath()
            }
            .fill(Color(nsColor: .windowBackgroundColor))
            .offset(y: 5),
            alignment: .bottom
        )
        .padding(.bottom, 6)
    }
}
