import XCTest
@testable import PokeDexBar

/// 오늘의 목표 — 굴림·세기·수령·롤오버.
@MainActor
final class DailyQuestTests: XCTestCase {
    private let today = "2026-09-03"

    private func makeStore(seed: UInt64 = 42) -> PlayerStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("daily-\(UUID().uuidString).json")
        let store = PlayerStore(fileURL: url, rng: SeededRNG(seed: 3),
                                now: { Date(timeIntervalSince1970: 1_700_000_000) })
        store.mutate { $0.lastDate = self.today; $0.offerSeed = seed }
        return store
    }

    // MARK: 굴림

    func testThreeQuestsADay() {
        XCTAssertEqual(DailyQuest.roll(date: today, seed: 42).count, DailyQuest.dailyCount)
    }

    /// 같은 종류가 두 번 서면 사실상 한 줄이다 — "알 3개"와 "알 5개"가 나란히 서면 안 된다.
    func testTheThreeQuestsAreAllDifferentKinds() {
        for day in 1...60 {
            let quests = DailyQuest.roll(date: "2026-09-\(day)", seed: 42)
            XCTAssertEqual(Set(quests.map(\.kind)).count, quests.count, "\(day)일: 종류가 겹쳤다")
        }
    }

    func testTheSameDayAndSeedAlwaysRollTheSame() {
        XCTAssertEqual(DailyQuest.roll(date: today, seed: 42),
                       DailyQuest.roll(date: today, seed: 42))
    }

    /// **날짜 축** — 날이 바뀌면 과제도 바뀐다(적어도 자주).
    func testDifferentDaysRollDifferently() {
        let days = (1...30).map { DailyQuest.roll(date: "2026-09-\($0)", seed: 42) }
        XCTAssertGreaterThan(Set(days.map { $0.map(\.id).joined() }).count, 5,
                             "한 달 내내 거의 같은 과제가 나온다")
    }

    /// **사람 축** — 이게 없으면 같은 날 지구상 모든 설치가 같은 과제를 받는다(박사의 제안이
    /// 실제로 그렇게 나갔다). 시드가 함수 시그니처에 없으면 이 질문을 할 수조차 없다.
    func testTwoPlayersGetDifferentQuests() {
        let differing = (1...30).count { day in
            let date = "2026-09-\(day)"
            return DailyQuest.roll(date: date, seed: 1) != DailyQuest.roll(date: date, seed: 2)
        }
        XCTAssertGreaterThan(differing, 20, "사람이 달라도 과제가 거의 같다")
    }

    /// 목표치는 그 종류가 실제로 낼 수 있는 값이어야 한다.
    func testEveryRolledTargetComesFromItsKindsOwnList() {
        for day in 1...60 {
            for quest in DailyQuest.roll(date: "2026-09-\(day)", seed: 7) {
                XCTAssertTrue(DailyQuest.targets(for: quest.kind).contains(quest.target),
                              "\(quest.kind) 에 없는 목표치 \(quest.target)")
            }
        }
    }

    // MARK: 보상

    /// **포인트여야 한다**(사용자 결정). 사탕으로 매일 셋을 주면 상점가로 하루 1.5B 어치가 되어
    /// 실사용 수입(500M/일)을 몇 배로 넘긴다 — 상점이 뜻을 잃는다.
    func testQuestsPayPointsAndOnlyTheBonusPaysCandy() {
        for quest in DailyQuest.pool {
            XCTAssertGreaterThan(DailyQuest.points(for: quest), 0)
            XCTAssertLessThanOrEqual(DailyQuest.points(for: quest), 15,
                                     "한 과제가 커먼 제안(10P)을 크게 넘는다")
        }
        XCTAssertEqual(DailyQuest.completionBonus, .item(.expCandy, 1))
    }

    /// 어려운 목표가 더 준다 — 안 그러면 쉬운 것만 고르는 게 항상 이득이다.
    ///
    /// **엄격히 커져야 한다.** 처음엔 "줄지만 않으면 된다"(`points == points.sorted()`)로 썼는데,
    /// 전부 같은 값으로 만드는 뮤테이션이 그대로 통과했다 — 정렬 비교는 평평한 값을 못 잡는다.
    func testHarderTargetsPayMore() {
        for kind in DailyQuest.Kind.allCases {
            let targets = DailyQuest.targets(for: kind)
            let points = targets.map { DailyQuest.points(for: .init(kind: kind, target: $0)) }
            for (easier, harder) in zip(points, points.dropFirst()) {
                XCTAssertGreaterThan(harder, easier, "\(kind): 목표가 커지는데 보상이 그대로다")
            }
        }
    }

    // MARK: 세기

    func testDrawingAnEggCountsOnlyWhenItSucceeds() {
        let store = makeStore()
        store.seedForTesting(wallet: EggBalance.drawPrice, slots: 1, eggs: 0,
                             at: Date(timeIntervalSince1970: 1_700_000_000))
        store.mutate { $0.lastDate = self.today }
        XCTAssertNotNil(store.startEgg(grade: .common, speciesID: 1, shiny: false))
        XCTAssertEqual(store.state.dailyCounts[DailyQuest.Kind.drawEggs.rawValue], 1)
        // 지갑도 슬롯도 없으니 거절된다 — 거절까지 세면 목표가 저절로 차오른다.
        XCTAssertNil(store.startEgg(grade: .common, speciesID: 1, shiny: false))
        XCTAssertEqual(store.state.dailyCounts[DailyQuest.Kind.drawEggs.rawValue], 1)
    }

    /// 셀 수 있는 활동 여섯 가지가 **전부 어딘가에서 불린다**. 종류를 더하고 호출을 안 붙이면
    /// 영영 0 에 머무는 과제가 생기는데, 그건 화면만 봐서는 "운이 나빴나" 로 읽힌다.
    func testEveryKindIsCountedSomewhereInTheStore() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/PokeDexBar/Player")
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        let source = files.filter { $0.pathExtension == "swift" }
            .compactMap { try? String(contentsOf: $0, encoding: .utf8) }.joined()
        // 주석을 먼저 걷어낸다 — 통짜 검색은 바로 위 주석의 같은 낱말에 걸린다.
        let code = source.split(separator: "\n")
            .map { $0.contains("//") ? String($0[..<$0.range(of: "//")!.lowerBound]) : String($0) }
            .joined(separator: "\n")
        for kind in DailyQuest.Kind.allCases {
            XCTAssertTrue(code.contains("countDailyActivity(.\(kind.rawValue)"),
                          "\(kind.rawValue) 를 세는 자리가 없다 — 그 과제는 영영 안 끝난다")
        }
    }

    // MARK: 수령

    func testClaimingPaysPointsOnceAndOnlyWhenDone() {
        let store = makeStore()
        let quest = store.dailyQuests[0]
        XCTAssertFalse(store.claimDailyQuest(quest), "달성 전에 받아졌다")

        store.countDailyActivity(quest.kind, by: quest.target)
        let before = store.state.researchPoints
        XCTAssertTrue(store.claimDailyQuest(quest))
        XCTAssertEqual(store.state.researchPoints, before + DailyQuest.points(for: quest))
        XCTAssertFalse(store.claimDailyQuest(quest), "같은 과제를 두 번 받았다")
    }

    /// 덤의 조건은 **달성이 아니라 수령**이다 — 아니면 하나도 안 누르고 덤만 가져갈 수 있다.
    func testTheBonusNeedsEveryQuestClaimedNotJustDone() {
        let store = makeStore()
        for quest in store.dailyQuests { store.countDailyActivity(quest.kind, by: quest.target) }
        XCTAssertFalse(store.dailyBonusReady, "다 하기만 했는데 덤이 열렸다")

        for quest in store.dailyQuests { XCTAssertTrue(store.claimDailyQuest(quest)) }
        XCTAssertTrue(store.dailyBonusReady)
        XCTAssertTrue(store.claimDailyBonus())
        XCTAssertEqual(store.count(of: .expCandy), 1)
        XCTAssertFalse(store.claimDailyBonus(), "덤을 두 번 받았다")
    }

    // MARK: 롤오버

    /// 날이 바뀌면 오늘치가 비워진다 — 오늘 토큰과 **같은 자리**에서. 판정이 두 곳이면 갈린다.
    func testANewDayClearsTodaysProgress() {
        let store = makeStore()
        store.seedForTesting(wallet: 0, slots: 3, eggs: 0, at: Date(timeIntervalSince1970: 1_700_000_000))
        store.mutate { s in
            s.lastDate = self.today
            s.installBaselineSet = true
            s.dailyCounts = ["drawEggs": 5]
            s.claimedDailyQuests = ["drawEggs-5"]
            s.claimedDailyBonus = true
        }
        store.update(todayTokens: 0, todayDate: "2026-09-04", hasUsageData: true)
        XCTAssertTrue(store.state.dailyCounts.isEmpty, "어제 횟수가 남았다")
        XCTAssertTrue(store.state.claimedDailyQuests.isEmpty, "어제 수령 기록이 남았다")
        XCTAssertFalse(store.state.claimedDailyBonus)
    }

    /// 같은 날의 갱신은 안 지운다 — 대조군. 없으면 "매번 비운다" 도 위를 통과한다.
    func testTheSameDayKeepsItsProgress() {
        let store = makeStore()
        store.seedForTesting(wallet: 0, slots: 3, eggs: 0, at: Date(timeIntervalSince1970: 1_700_000_000))
        store.mutate { s in
            s.lastDate = self.today
            s.installBaselineSet = true
            s.dailyCounts = ["drawEggs": 5]
        }
        store.update(todayTokens: 0, todayDate: today, hasUsageData: true)
        XCTAssertEqual(store.state.dailyCounts["drawEggs"], 5)
    }

    /// **오늘의 목표는 홈에 있다**(사용자 판단). 도감 탭에 두면 자주 안 여는 화면에 하루짜리가
    /// 갇혀, 있는 줄도 모르고 하루가 지난다. 뷰를 옮겨 놓고 홈에 붙이는 걸 잊는 부류를 막는다 —
    /// 성별 보정이 뷰에 매달려 영영 안 돌던 것과 같은 배선 공백이라 소스로 확인한다.
    func testTheDailyGoalsLiveOnHome() throws {
        let ui = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/PokeDexBar/UI")
        func code(_ file: String) throws -> String {
            let text = try String(contentsOf: ui.appendingPathComponent(file), encoding: .utf8)
            // 주석을 먼저 걷어낸다 — 통짜 검색은 바로 위 주석의 같은 낱말에 걸린다.
            return text.split(separator: "\n")
                .map { $0.contains("//") ? String($0[..<$0.range(of: "//")!.lowerBound]) : String($0) }
                .joined(separator: "\n")
        }
        XCTAssertTrue(try code("PopoverView.swift").contains("DailyGoalsView(store:"),
                      "홈이 오늘의 목표를 안 그린다")
        XCTAssertFalse(try code("NationalDexView.swift").contains("DailyGoalsView"),
                       "도감 탭에 아직 남아 있다 — 두 곳에 있으면 하나만 고쳐진다")
    }

    /// 세 언어 모두 문장이 있어야 한다 — 종류를 더하고 번역을 빼먹으면 그 줄이 빈칸이 된다.
    func testEveryKindHasASentenceInEveryLanguage() {
        for lang in AppLanguage.allCases {
            let l = L(lang)
            for kind in DailyQuest.Kind.allCases {
                for target in DailyQuest.targets(for: kind) {
                    let text = l.dailyQuestLabel(kind, target)
                    XCTAssertFalse(text.isEmpty, "\(lang)/\(kind)")
                    XCTAssertTrue(text.contains("\(target)"), "\(lang)/\(kind): 목표치가 문장에 없다")
                }
            }
            XCTAssertFalse(l.dailySection.isEmpty)
            XCTAssertFalse(l.dailyBonusLabel.isEmpty)
        }
    }
}
