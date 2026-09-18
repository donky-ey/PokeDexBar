import SwiftUI

/// 홈의 부화 슬롯 줄. 알은 종을 숨긴 채 남은 시간만 보여준다 — 무엇이 나올지는 깨야 안다.
///
/// 슬롯 폭은 `PopoverMetrics.contentWidth`(332pt)를 넘을 수 있다 — `EggBalance.maxSlots`(6)까지
/// 슬롯을 늘리면 `rowWidth(forSlotCount:)` 가 342pt(= 6×52 + 5×6)를 반환해 6pt 초과한다.
/// `ProviderTabBar`(PopoverView.swift, 프로바이더 탭 줄이 439pt vs 332pt 로 넘쳤을 때와 같은 문제)와
/// 동일하게 가로 `ScrollView` 로 감싸 잘리는 대신 스크롤되게 한다.
struct EggSlotsView: View {
    let store: PlayerStore
    /// 1초 틱 — 남은 시간이 살아 움직이게. 호출부(PopoverView)가 이 뷰만 `TimelineView` 로
    /// 감싸 넘긴다 — 홈 탭 전체를 매초 다시 그리지 않기 위해서다.
    let now: Date
    /// 종 번호 → 진화 라인. 거둔 개체의 **이름**을 보여주려면 필요하다(번호만으로는 무엇이
    /// 나왔는지 와닿지 않는다). 아직 없으면 `onNeedLine` 으로 요청하고 번호로 떨어진다.
    var lines: [Int: EvoLine] = [:]
    var onNeedLine: (Int) -> Void = { _ in }
    /// 뽑기가 종을 고르려면 후보 인덱스가 필요하다. **뽑기가 상점에서 여기로 온 이유**는
    /// 그 결과가 놓이는 자리가 여기이기 때문이다 — 빈 슬롯을 요구하고, 빈 슬롯 수를 보여 주고,
    /// 뽑으면 그 칸에 알이 떨어지는데, 정작 버튼만 다른 탭에 있었다(사용자 지적).
    var provider: (any PokeProviding)?
    /// 방금 거둔 개체 — 연출 중에만 non-nil. 이미 박스에 들어가 있어서 닫아도 잃는 것이 없다.
    @State private var hatched: Individual?
    /// 뽑기 연출 — 등급·이로치만 안다(무엇이 나왔는지는 깨야 안다).
    @State private var reveal: (grade: Grade, shiny: Bool)?
    @State private var drawing = false
    @State private var drawError: String?
    @State private var drawTask: Task<Void, Never>?

    nonisolated private static let tileSize: CGFloat = 52
    nonisolated private static let tileSpacing: CGFloat = 6

    private var l: L { store.l }

    /// 남은 시간 표기. 단위는 큰 것 두 개까지만 — "1일 1시간", "3시간 12분", "1분 30초".
    /// 올림(`rounded(.up)`) — 잘라내면(`Int(remaining)`) 0.x초가 남았을 때도 0으로 떨어져
    /// 실제로 부화하기 최대 1초 전부터 "부화!"라고 먼저 말해버린다.
    nonisolated static func countdownText(_ remaining: TimeInterval, _ lang: AppLanguage) -> String {
        let l = L(lang)
        let s = Int(remaining.rounded(.up))
        guard s > 0 else { return l.eggHatchingNow }
        let days = s / 86_400, hours = (s % 86_400) / 3600
        let minutes = (s % 3600) / 60, seconds = s % 60
        if days > 0 { return l.eggCountdownDaysHours(days, hours) }
        if hours > 0 { return l.eggCountdownHoursMinutes(hours, minutes) }
        if minutes > 0 { return l.eggCountdownMinutesSeconds(minutes, seconds) }
        return l.eggCountdownSeconds(seconds)
    }

    /// 슬롯 `count`개를 한 줄에 나란히 놓았을 때 필요한 폭. `ScrollView` 없이 이 값이
    /// `PopoverMetrics.contentWidth` 를 넘으면 잘린다 — 타일 크기를 바꿀 때 이 함수와
    /// `slot(_:)`/`emptySlot` 의 프레임이 항상 같은 상수(`tileSize`/`tileSpacing`)를 쓰므로 드리프트 없이 같이 움직인다.
    nonisolated static func rowWidth(forSlotCount count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        return CGFloat(count) * tileSize + CGFloat(count - 1) * tileSpacing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(l.eggSlotsHeader).font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                // 재화가 여기 온 이유: 빈 칸 버튼이 회색일 때 **지갑 때문인지 자리 때문인지**를
                // 이 줄에서 가릴 수 있어야 한다. 둘 다 이 한 줄에 있다.
                Text(TokenFormatter.compact(store.state.wallet))
                    .font(.system(size: 9, weight: .medium)).monospacedDigit()
                    .foregroundStyle(.secondary)
                Text("\(store.state.eggs.count) / \(store.state.slots)")
                    .font(.system(size: 9)).monospacedDigit().foregroundStyle(.tertiary)
            }
            // **뽑기 칸은 스크롤 바깥이다.** 줄 안에 두면 두 가지를 잃는다: 알이 찰 때마다
            // 자리가 밀려 연타가 깨지고(사용자 지적), 칸 하나가 늘어난 만큼 줄이 더 일찍 넘쳐
            // 오른쪽 알을 보려고 스크롤하면 **버튼이 화면 밖으로 나간다**(5슬롯부터 그렇다).
            // 스크롤의 형제로 두면 둘 다 사라진다 — 자리가 고정되고 늘 보인다.
            HStack(alignment: .top, spacing: 10) {
                if provider != nil {
                    drawSlot
                    // 왼쪽은 **동작**이고 오른쪽은 **상태**다 — 같은 크기 타일이 붙어 서면 한 덩어리로
                    // 읽히므로 경계를 한 줄 긋는다.
                    Divider().frame(height: Self.tileSize)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Self.tileSpacing) {
                        ForEach(Self.tiles(eggs: store.state.eggs, slots: store.state.slots)) { tile in
                            switch tile {
                            case .egg(let egg): slot(egg)
                            case .empty: emptySlot
                            }
                        }
                    }
                }
                // 슬롯이 적으면(대부분의 사용자) 스크롤·바운스가 생기지 않아 기존과 동일하게 보인다.
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            }
            // **툴팁이 아니라 인라인 한 줄이다.** 팝오버 안에서는 `.help` 가 안 뜬다(실사용 확인) —
            // 이 앱의 다른 `.help` 들도 마찬가지라, 안 보이는 곳에 설명을 두면 없는 것과 같다.
            //
            // 확률은 값 바로 아래에 — 10M 이 무엇을 사는 값인지 말해 준다.
            // 자리가 없으면 확률이 아니라 **왜 못 뽑는지**가 이 자리에 와야 한다 — 회색 버튼만
            // 두면 물어볼 곳이 없다. 자리가 있으면 확률이 값(10M)이 무엇을 사는지 말해 준다.
            Text(Self.footnote(freeSlots: store.freeSlots, language: store.language))
                .font(.system(size: 8)).foregroundStyle(.tertiary)
            if let drawError {
                Text(drawError).font(.system(size: 9)).foregroundStyle(.orange)
            }
            // 확정권은 **뽑기 바로 아래**가 자리다(상점에 있을 때부터 그랬다) — 개봉이 늘 알이
            // 태어나는 자리에서 일어나야 한다. 가진 것이 있을 때만 선다.
            // 가진 확정권만 선다. 목록을 손으로 적으면 새 확정권이 조용히 안 보인다.
            ForEach(ShopItem.allCases.filter {
                ($0.guaranteedGrade != nil || $0.guaranteedGeneration != nil)
                    && store.count(of: $0) > 0
            }, id: \.self) { ticket in
                Button(l.shopTicketDraw(ticket.label(store.language), store.count(of: ticket))) {
                    drawWithTicket(ticket)
                }
                .buttonStyle(.bordered).controlSize(.mini)
                .disabled(store.freeSlots == 0 || drawing)
            }
            // 감면은 알마다가 아니라 부화 전체에 걸리는 상태라 슬롯이 아니라 줄 아래 한 번 적는다.
            // 이게 없으면 카운트다운만 짧아져서 왜 빨라졌는지 알 길이 없다.
            if let warmer = HatchSpeedup.warmer(in: store.state.box) {
                HStack(spacing: 3) {
                    Image(systemName: "flame.fill").font(.system(size: 8)).foregroundStyle(.orange)
                    Text(warmedHint).font(.system(size: 9)).foregroundStyle(.tertiary)
                }
                .task(id: warmer.displayLineID) {
                    // 이름은 네트워크로 오는 값이다 — 없으면 요청해 두고, 오는 대로 문장이 채워진다.
                    if lines[warmer.displayLineID] == nil { onNeedLine(warmer.displayLineID) }
                }
            }
        }
        .onChange(of: now) { _, date in announceRipeEggs(at: date) }
        // 거둔 개체를 한 번 보여준다 — 확인을 누른 보람이 있어야 하고, 이걸 안 보면 무엇이
        // 나왔는지 박스에 들어가서야 알게 된다.
        .overlay {
            if let reveal {
                EggRevealView(grade: reveal.grade, shiny: reveal.shiny, l: l,
                              language: store.language) { self.reveal = nil }
            }
        }
        .overlay {
            if let hatched {
                HatchedRevealView(individual: hatched, store: store,
                                  line: lines[hatched.displayLineID], onNeedLine: onNeedLine) {
                    self.hatched = nil
                }
            }
        }
    }

    /// 카운트다운이 부화 시각을 지나면 그 틱에서 알린다. 이게 없으면 팝오버를 열어 둔 채 시간이
    /// 찬 알이 조용히 "부화!"로만 바뀌고 알림은 다음 사용량 새로고침에야 나간다 — 새로고침을
    /// "수동"으로 둔 사용자(`UsageStore` 의 0초 프리셋)는 타이머가 아예 없어 영영 안 나간다.
    /// 이미 도는 1초 틱에 얹으므로 새 타이머는 없고, 익은 알이 없으면 아무 일도 하지 않는다.
    /// **거두는 건 여기서 하지 않는다** — 그건 사용자가 확인을 눌러야 한다.
    /// 감면을 준 아이의 이름을 넣은 안내. 라인이 아직 없으면 요청하고 일반 문구로 떨어진다 —
    /// 이름이 번호(`#663`)로 나오느니 "어떤 아이 덕"이라고만 말하는 편이 낫다.
    private var warmedHint: String {
        guard let warmer = HatchSpeedup.warmer(in: store.state.box) else { return l.eggWarmedHint }
        guard let name = lines[warmer.displayLineID]?
                .localizedName(warmer.displaySpeciesID, store.language) else {
            return l.eggWarmedHint
        }
        return l.eggWarmedBy(warmer.displayName(speciesName: name, store.language))
    }

    private func announceRipeEggs(at date: Date) {
        guard store.readyEggCount(at: date) > 0 else { return }
        store.announceReadyEggsAndNotify(at: date)
    }

    private func slot(_ egg: Egg) -> some View {
        let remaining = egg.remaining(at: now)
        let ready = remaining <= 0
        return VStack(spacing: 1) {
            EggIcon(grade: egg.grade, size: ready ? 19 : 21, cracked: ready)
            if ready {
                // 확인을 눌러야 개체가 되어 박스로 간다 — 무엇이 나왔는지 못 보고 지나가지 않게.
                Button(l.eggClaim) { claim(egg) }
                    .buttonStyle(.plain)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5).padding(.vertical, 1.5)
                    .background(Color.accentColor, in: Capsule())
            } else {
                Text(Self.countdownText(remaining, store.language))
                    .font(.system(size: 8)).monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Text(egg.grade.label(store.language))
                .font(.system(size: 7, weight: .semibold)).foregroundStyle(.tertiary)
        }
        .frame(width: Self.tileSize, height: Self.tileSize)
        .background(ready ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 8))
    }

    private func claim(_ egg: Egg) {
        guard let individual = store.claimHatch(eggID: egg.id, at: now) else { return }
        hatched = individual
    }

    /// **빈 칸이 곧 뽑기 버튼이다.** 옆에 버튼을 따로 두면 빈 칸이 장식이 되고 누를 곳이
    /// 둘로 갈린다(키우미집 빈 자리에서 쓴 것과 같은 판단).
    /// 스크롤되는 줄에 놓이는 칸들 — 알과 빈 칸뿐이다. **뽑기 칸은 여기 없다**: 줄 안에 두면
    /// 알이 찰 때마다 자리가 밀려 연타가 깨지고, 줄이 한 칸 더 길어져 스크롤하면 버튼이 화면
    /// 밖으로 나간다. 케이스를 아예 안 두는 이유는 그 회귀를 테스트가 아니라 **컴파일**이
    /// 막게 하려는 것이다.
    ///
    /// 순서를 뷰 본문에 두면 "알이 늘어도 줄 길이가 그대로인가"를 물어볼 수가 없어서 밖으로 뺐다.
    enum RowTile: Identifiable {
        case egg(Egg)
        case empty(Int)

        var id: String {
            switch self {
            case .egg(let egg): "egg-\(egg.id)"
            case .empty(let index): "empty-\(index)"
            }
        }
    }

    static func tiles(eggs: [Egg], slots: Int) -> [RowTile] {
        eggs.map { RowTile.egg($0) } + (0..<max(0, slots - eggs.count)).map { RowTile.empty($0) }
    }

    /// 줄 아래 한 줄. 자리가 없으면 확률이 아니라 **왜 못 뽑는지**가 온다 — 회색 버튼만 두면
    /// 물어볼 곳이 없다. 지갑 부족은 헤더에 지갑과 값이 나란히 서서 이미 읽히므로 문장을 안 만든다.
    nonisolated static func footnote(freeSlots: Int, language: AppLanguage) -> String {
        freeSlots == 0 ? L(language).eggSlotsFull : oddsText(language)
    }

    private var drawSlot: some View {
        let canDraw = store.canDraw && !drawing && provider != nil
        // **점선은 빈 칸 전용이다** — 버튼까지 점선이면 셋(버튼·빈칸·알)이 같은 무게로 읽힌다.
        // 그리고 **악센트(초록)를 안 쓴다**: 이 줄에서 가장 중요한 신호는 "지금 열 수 있는 알"의
        // 초록 배지인데, 바로 옆에 초록 버튼이 서면 시선이 갈린다. 버튼다움은 색이 아니라
        // 채운 카드 + `plus` + 값이 맡는다.
        return Button { draw() } label: {
            //
            // 색을 뺀 만큼 **눌리는 상태와 막힌 상태는 밝기로** 갈린다 — 처음엔 둘을 같은 회색으로
            // 뒀더니 지갑이 모자란 줄과 아닌 줄이 구별되지 않았다(스크린샷으로 발각).
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(canDraw ? 0.16 : 0.06))
                .strokeBorder(Color.secondary.opacity(canDraw ? 0.30 : 0.12), lineWidth: 1)
                .frame(width: Self.tileSize, height: Self.tileSize)
                .overlay {
                    // 옆 알 칸과 **같은 문법**이다 — 그림 / 한 줄 / 작은 한 줄. 나란히 서면
                    // "이걸 누르면 저게 하나 생긴다"로 읽힌다.
                    VStack(spacing: 1) {
                        // 실루엣은 **글자보다 한 단 낮게**. 흰 알로 두면 줄에서 가장 밝은 것이 돼서
                        // `Open` 배지(이 줄의 주인공)를 눌러버린다 — 회색 알이 "아직 모른다"는
                        // 뜻에도 맞는다. 버튼의 정체는 글자가 맡는다.
                        drawGlyph
                            .foregroundStyle(canDraw ? AnyShapeStyle(.secondary)
                                                     : AnyShapeStyle(.tertiary))
                        // **`plus` 를 쓰면 안 된다** — 이 앱은 부화 슬롯을 실제로 돈 받고 팔아서,
                        // 슬롯 줄에 선 `+` 는 "슬롯 추가"로 읽힌다(사용자 지적). 하는 일을 글자로 적는다.
                        Text(l.shopDrawButton)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(canDraw ? AnyShapeStyle(.primary)
                                                     : AnyShapeStyle(.tertiary))
                        // 값은 **회색일 때도 보인다** — 얼마가 모자란지 알아야 기다릴 수 있다.
                        Text(TokenFormatter.compact(EggBalance.drawPrice))
                            .font(.system(size: 7, weight: .semibold)).monospacedDigit()
                            .foregroundStyle(canDraw ? AnyShapeStyle(.secondary)
                                                     : AnyShapeStyle(.tertiary))
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(!canDraw)
    }

    /// 뽑기 칸의 그림. **등급 없는 알**이어야 한다 — 커먼 알 그림을 그대로 쓰면 "커먼이
    /// 나온다"로 읽히는데, 무엇이 나올지는 뽑아야 안다. 그래서 같은 그림을 실루엣(템플릿)으로
    /// 쓴다. CALayer 필터(`.brightness` 류)로 어둡게 하는 방법은 스크린샷 생성기의 그리기
    /// 경로에서 빠지므로 쓰지 않는다(도감 실루엣이 같은 이유로 템플릿 렌더링을 쓴다).
    @ViewBuilder private var drawGlyph: some View {
        if drawing {
            Image(systemName: "hourglass").font(.system(size: 14, weight: .semibold))
        } else if let art = EggIcon.image(for: .common) {
            Image(nsImage: art).resizable().renderingMode(.template)
                .interpolation(.high).scaledToFit().frame(width: 15, height: 18)
        }
    }

    private var emptySlot: some View {
        RoundedRectangle(cornerRadius: 8)
            .stroke(Color.secondary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [3]))
            .frame(width: Self.tileSize, height: Self.tileSize)
    }
    /// 등급·이로치를 굴리고, 그 등급 안에서 베이스 종을 포획률 가중으로 고른다(`EggBalance.pickSpecies`).
    /// 후보는 네트워크(베이스 인덱스)라 여기서 받아 스토어에 넘긴다.
    private func draw() {
        drawing = true
        drawError = nil
        drawTask = Task {
            defer { drawing = false }
            let roll = store.rollGradeAndShiny()
            guard let provider, let index = try? await provider.baseSpeciesIndex(),
                  !index.isEmpty else {
                // 그 사이 뷰가 사라져 취소됐으면(팝오버 닫힘 등) 착지하지 않는다.
                guard !Task.isCancelled else { return }
                drawError = l.shopDrawFetchFailed
                return
            }
            // 그 사이 뷰가 사라져 취소됐으면(팝오버 닫힘 등) 착지하지 않는다 — 늦게 도착한
            // 조회가 다음 뽑기와 경합해 조용히 이기는 걸 막는다.
            guard !Task.isCancelled else { return }
            var chosen = EggBalance.pickSpecies(from: index, grade: roll.grade, roll: store.nextRandomUnit())
            // 메타몽은 일반 후보 풀에서 빠져 있어(`PokeAPIClient`) 여기서만 들어온다 — 커먼 1/128.
            // 종을 고른 **뒤에** 굴려 덮어쓴다. 앞에 두면 이 굴림이 후보 선택의 난수를 밀어내
            // 기존 뽑기 결과가 통째로 달라진다.
            if DittoDisguise.hits(grade: roll.grade, roll: store.nextRandomUnit()) {
                chosen = DittoDisguise.speciesID
            }
            // 고른 종의 성장 타입을 인덱스에서 찾아 그대로 싣는다. 메타몽은 인덱스 자체에서
            // 빠져 있어(`PokeAPIClient`) 못 찾으면 기본값(`.mediumFast`)으로 태어나는데,
            // 실제로도 메타몽의 성장 타입이 미디엄패스트라 값이 어긋나지 않는다.
            let entry = index.first(where: { $0.id == chosen })
            let growthRate = entry?.growthRate ?? .mediumFast
            let genderRate = entry?.genderRate ?? GenderBalance.defaultRate
            drawError = Self.landDraw(store, grade: roll.grade, speciesID: chosen, shiny: roll.shiny,
                                      growthRate: growthRate, genderRate: genderRate)
            // 착지에 실패했으면(슬롯이 찼다 등) 축하할 것이 없다 — 문구만 남긴다.
            if drawError == nil { reveal = (roll.grade, roll.shiny) }
        }
    }

    /// 확정권 한 장을 쓴다. **등급권**은 등급을 고정하고 종은 평소대로 고르며,
    /// **세대권**은 종의 후보를 그 세대로 좁히고 등급은 평소 확률로 굴린다.
    private func drawWithTicket(_ ticket: ShopItem) {
        guard let provider, !drawing else { return }
        drawing = true
        drawError = nil
        drawTask = Task {
            defer { drawing = false }
            guard let index = try? await provider.baseSpeciesIndex(), !index.isEmpty else {
                drawError = l.shopDrawFetchFailed
                return
            }
            let pool = ticket.guaranteedGeneration.map {
                EggBalance.speciesIndex(index, inGeneration: $0)
            } ?? index
            guard !pool.isEmpty else {
                drawError = l.shopDrawFetchFailed
                return
            }
            let grade = ticket.guaranteedGrade
                ?? EggBalance.rollGrade(store.nextRandomUnit())
            let chosen = EggBalance.pickSpecies(from: pool, grade: grade,
                                                roll: store.nextRandomUnit())
            // 성장곡선·성비는 인덱스에서 그대로 싣는다 — 일반 뽑기(`draw()`)와 같은 규칙.
            let entry = index.first(where: { $0.id == chosen })
            let growthRate = entry?.growthRate ?? .mediumFast
            let genderRate = entry?.genderRate ?? GenderBalance.defaultRate
            guard let egg = store.redeemEggTicket(ticket, grade: grade, speciesID: chosen,
                                                  growthRate: growthRate, genderRate: genderRate) else {
                drawError = l.shopDrawUnavailable
                return
            }
            reveal = (grade: egg.grade, shiny: egg.shiny)
        }
    }

    /// 뽑기 확률 표기. 밸런스 표에서 만들어 문구와 수치가 어긋나지 않게 한다.
    /// 언어는 필수 인자다(`AppLanguage` 의 "미정" 관례는 `.systemDefault` — `.ko` 를 기본값으로
    /// 두면 이 파일만 다른 컨벤션을 갖게 된다). 화면에서는 스토어 언어를 그대로 넘긴다.
    nonisolated static func oddsText(_ lang: AppLanguage) -> String {
        EggBalance.odds
            .map { "\($0.grade.label(lang)) \(Int($0.probability * 100))%" }
            .joined(separator: " · ")
    }

    /// 뽑기 착지 — 알을 슬롯에 넣고, 못 넣었으면 보여줄 문구를 돌려준다(nil = 성공).
    /// `startEgg` 은 착지 시점에 `canDraw` 가 아니면 nil 을 돌려준다: 후보를 기다리는 동안에도
    /// 슬롯·아이템 버튼은 살아 있어 지갑이 뽑기 값 아래로 내려갈 수 있다. 그 nil 을 버리면
    /// 사용자는 눌렀는데 재화도 안 줄고 알도 안 생기는 침묵을 본다.
    /// 뷰 밖에서 잠글 수 있게 착지 지점만 떼어 둔다(`draw()` 는 네트워크 await 라 통째로는 못 잡는다).

    /// 뽑은 알을 슬롯에 놓는다. 실패하면(자리가 없다 등) 문구를 돌려준다.
    static func landDraw(_ store: PlayerStore, grade: Grade, speciesID: Int, shiny: Bool,
                         growthRate: GrowthRate = .mediumFast,
                         genderRate: Int = GenderBalance.defaultRate) -> String? {
        store.startEgg(grade: grade, speciesID: speciesID, shiny: shiny,
                       growthRate: growthRate, genderRate: genderRate) == nil
            ? store.l.shopDrawUnavailable : nil
    }

}
