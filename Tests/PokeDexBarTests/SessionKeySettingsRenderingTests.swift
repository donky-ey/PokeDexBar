import AppKit
import SwiftUI
import XCTest
@testable import PokeDexBar

/// Used for the optional keyboard-focus check on an interactive desktop.
private final class SessionKeyTestWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

/// #275: 만료 안내에서 설정으로 들어오면 고급 섹션이 펼쳐지고 세션 키 입력란이 뷰포트 안에
/// 보여야 한다 — 접힌 disclosure 안에 숨어 있으면 안내가 막다른 길이 된다.
/// (포크: CompanionStore·난이도 슬라이더 단언은 업스트림 전용이라 기존 슬라이더 보존으로 치환.)
@MainActor
final class SessionKeySettingsRenderingTests: XCTestCase {
    /// May a scroll that never landed be skipped instead of failed? Only while the display sleeps, and
    /// never on CI, where a skip would make the check silently disappear.
    ///
    /// SwiftUI lands `scrollTo` in the window's display cycle, which stops while the display sleeps.
    /// Measured on a locked Mac: the section still expands, but the scroll never lands, even with
    /// animations disabled (the old fixed-sleep version failed there 3/3 as well). An unattended local
    /// gate run meets this; a hosted runner keeps its display awake.
    nonisolated static func excusesMissingScroll(displayAsleep: Bool, environment: [String: String]) -> Bool {
        displayAsleep && environment["CI"] == nil && environment["GITHUB_ACTIONS"] == nil
    }

    func testASleepingDisplayExcusesTheScrollOnlyOffCI() {
        XCTAssertTrue(Self.excusesMissingScroll(displayAsleep: true, environment: [:]))
        XCTAssertFalse(Self.excusesMissingScroll(displayAsleep: false, environment: [:]))
        XCTAssertFalse(Self.excusesMissingScroll(displayAsleep: true, environment: ["CI": "true"]))
        XCTAssertFalse(Self.excusesMissingScroll(displayAsleep: true, environment: ["GITHUB_ACTIONS": "true"]))
    }

    func testSessionKeyEntryOpensInsideViewportAndPreservesExistingControls() async throws {
        let suite = "SessionKeySettingsRendering-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(suite).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let usage = UsageStore(providers: [], autoRefresh: false, defaults: defaults)
        let player = PlayerStore(fileURL: file, rng: SeededRNG(seed: 1))
        let navigation = PopoverNavigation()
        navigation.openSessionKeySettings()
        let host = NSHostingController(rootView: SettingsView(
            onClose: {}, startExpanded: navigation.expandAdvancedOnOpen)
            .environment(usage).environment(player).environment(UpdateChecker())
            .frame(width: PopoverMetrics.width))
        let previousKeyWindow = NSApp.keyWindow
        let window = SessionKeyTestWindow(
            contentRect: NSRect(x: -10000, y: -10000, width: PopoverMetrics.width, height: 460),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentViewController = host
        window.makeKeyAndOrderFront(nil)
        defer {
            window.orderOut(nil)
            previousKeyWindow?.makeKey()
        }
        func sessionKeyEntry() -> NSSecureTextField? {
            host.view.layoutSubtreeIfNeeded()
            return descendants(of: host.view).compactMap { $0 as? NSSecureTextField }.first
        }

        // None of these need the display, so they run whatever happens to the scroll below.
        let expanded = await waitUntil { sessionKeyEntry() != nil }
        // 기존 설정 컨트롤(경고/위험 임계 슬라이더 2개 — 펫 크기 슬라이더는 펫이 꺼진 기본값에선
        // 렌더되지 않는다)이 세션 키 섹션 병합 후에도 살아 있어야 한다.
        XCTAssertGreaterThanOrEqual(descendants(of: host.view).compactMap { $0 as? NSSlider }.count, 2,
                                    "existing sliders must survive the Settings merge")
        XCTAssertTrue(navigation.showSettings)
        navigation.reset()
        XCTAssertFalse(navigation.expandAdvancedOnOpen)
        guard expanded else { return XCTFail("the advanced section must open expanded") }

        // The scroll lands after a chain nobody times: first render → onAppear → a main-actor Task
        // queued behind that render → 80 ms → a 0.25 s animated scroll. Measured ~0.45 s on its own
        // and 0.58–1.03 s inside the full suite, where a fixed 500 ms sleep failed — wait for the field.
        // "Inside" alone would pass on one frame mid-animation, so a scroll that carries the field past
        // the viewport would pass too: wait until it is inside and has stopped moving for 150 ms, many
        // frames of that animation (they landed ~11 ms apart, measured).
        var lastRect: NSRect?
        var stillSince = ContinuousClock.now
        let settledInside = await waitUntil {
            guard let field = sessionKeyEntry() else { return false }
            let rect = field.convert(field.bounds, to: host.view)
            if rect != lastRect { lastRect = rect; stillSince = .now }
            return host.view.bounds.contains(rect) && ContinuousClock.now - stillSince >= .milliseconds(150)
        }
        if !settledInside {
            // Asked at the timeout, not up front: a display that falls asleep mid-wait counts too.
            if Self.excusesMissingScroll(displayAsleep: CGDisplayIsAsleep(CGMainDisplayID()) != 0,
                                         environment: ProcessInfo.processInfo.environment) {
                throw XCTSkip("the display is asleep, so the window never lands its scroll")
            }
            return XCTFail("session key entry must be visible after scrolling, and stay there")
        }
        // Hosted CI renders the layout but does not grant this XCTest window an editor.
        // Verify keyboard focus on an interactive Mac with PTB_VERIFY_KEYBOARD_FOCUS=1.
        if ProcessInfo.processInfo.environment["PTB_VERIFY_KEYBOARD_FOCUS"] == "1" {
            let secure = try XCTUnwrap(sessionKeyEntry())
            // Focus is set in the same Task as the scroll and reaches AppKit an update later.
            let focused = await waitUntil { secure.currentEditor() != nil }
            XCTAssertTrue(focused, "session key entry must receive keyboard focus")
            XCTAssertTrue(secure.currentEditor() === window.firstResponder)
        }
    }

    private func descendants(of view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { descendants(of: $0) }
    }
}
