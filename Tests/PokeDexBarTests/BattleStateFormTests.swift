import XCTest
@testable import PokeDexBar

/// 배틀 상태 폼 — 윽우지(먹이)와 모르페코(배고픔).
@MainActor
final class BattleStateFormTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeStore() -> PlayerStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bsf-\(UUID().uuidString).json")
        return PlayerStore(fileURL: url, rng: SeededRNG(seed: 1), now: { self.now })
    }

    private func cramorant(partner: Bool, stints: Int = 0) -> Individual {
        var made = Individual(baseID: 845, speciesID: 845, pathIDs: [845],
                              nature: .hardy, obtainedAt: now, grade: .rare)
        made.partnerSince = partner ? now : nil
        made.partnerStintsEnded = stints
        return made
    }

    // MARK: 윽우지

    /// **박스에 있는 동안은 절대 물지 않는다** — 사냥은 곁에 데리고 나갈 때의 일이다.
    func testCramorantNeverHoldsPreyWhileInTheBox() {
        for stints in 0..<200 {
            XCTAssertNil(cramorant(partner: false, stints: stints).spriteForm,
                         "박스에 있는데 먹이를 물었다(stints \(stints))")
        }
    }

    /// 곁에 두면 확률로 문다 — 세 모습이 **전부** 나와야 한다(한쪽으로 굳으면 확률이 죽은 것).
    func testCramorantEventuallyShowsAllThreeLooks() {
        var seen: Set<String> = []
        for stints in 0..<400 {
            seen.insert(cramorant(partner: true, stints: stints).spriteForm ?? "cramorant")
        }
        XCTAssertEqual(seen, ["cramorant", "cramorant-gulping", "cramorant-gorging"])
    }

    /// **한 번 곁에 둔 동안에는 안 바뀐다** — 매번 다시 굴리면 입에 든 것이 깜빡인다.
    func testThePreyStaysPutForTheWholeStint() {
        let one = cramorant(partner: true, stints: 3)
        let first = one.spriteForm
        for _ in 0..<50 { XCTAssertEqual(one.spriteForm, first, "같은 구간인데 물고 있는 게 바뀐다") }
    }

    /// 내렸다 다시 올리면(카운터 증가) 새로 굴린다.
    ///
    /// **같은 개체로 구간만 바꾼다** — 처음엔 매번 새 개체를 만들어 비교했는데, 그러면 id 축만으로도
    /// 값이 갈려서 구간 축을 빼도 통과했다(뮤테이션으로 발각). 결정적 굴림은 축마다 따로 물어야 한다.
    func testANewStintRollsAgain() {
        var one = cramorant(partner: true, stints: 0)
        var looks: Set<String> = []
        for stint in 0..<400 {
            one.partnerStintsEnded = stint
            looks.insert(one.spriteForm ?? "-")
        }
        XCTAssertGreaterThan(looks.count, 1, "같은 개체인데 구간이 바뀌어도 늘 같은 것을 물고 있다")
    }

    /// 개체가 다르면 같은 구간이어도 다를 수 있다 — 굴림에 "누구" 축이 들어 있는지(CLAUDE.md).
    func testTwoCramorantsDoNotShareOneRoll() {
        let looks = (0..<200).map { _ in cramorant(partner: true, stints: 0).spriteForm ?? "-" }
        XCTAssertGreaterThan(Set(looks).count, 1, "개체가 달라도 결과가 같다 — id 축이 빠졌다")
    }

    // MARK: 모르페코

    /// 기록이 없으면 배고프지 않다 — 켜자마자 배고픈 모습이면 그게 기본값처럼 보인다.
    func testNoRecordMeansNotHangry() {
        XCTAssertFalse(BattleStateForm.isHangry(lastTokenAt: nil, now: now))
    }

    /// 문턱 경계 — 딱 30분에 배고파진다.
    func testHungerCrossesExactlyAtTheThreshold() {
        let fed = now.addingTimeInterval(-BattleStateForm.hangryAfter)
        XCTAssertTrue(BattleStateForm.isHangry(lastTokenAt: fed, now: now))
        let justFed = now.addingTimeInterval(-BattleStateForm.hangryAfter + 1)
        XCTAssertFalse(BattleStateForm.isHangry(lastTokenAt: justFed, now: now))
    }

    /// 배고프면 다른 모습, 아니면 기본. **모르페코가 아닌 종은 배고파도 안 바뀐다.**
    func testOnlyMorpekoShowsHunger() {
        var morpeko = Individual(baseID: 877, speciesID: 877, pathIDs: [877],
                                 nature: .hardy, obtainedAt: now, grade: .rare)
        morpeko.hangry = true
        XCTAssertEqual(morpeko.spriteForm, "morpeko-hangry")
        morpeko.hangry = false
        XCTAssertNil(morpeko.spriteForm)

        var pikachu = Individual(baseID: 25, speciesID: 25, pathIDs: [25],
                                 nature: .hardy, obtainedAt: now, grade: .common)
        pikachu.hangry = true
        XCTAssertNil(pikachu.spriteForm, "모르페코가 아닌데 배고픈 모습이 붙었다")
    }

    /// 토큰이 들어오면 배부르고, **델타가 없는 틱에도** 시간이 지나면 배고파진다.
    /// 들어올 때만 갱신하면 배부른 채로 영영 안 바뀐다(정확히 반대로 동작한다).
    func testTheTickFeedsThenLetsItGetHangry() {
        var clock = now
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bsf-tick-\(UUID().uuidString).json")
        let store = PlayerStore(fileURL: url, rng: SeededRNG(seed: 1), now: { clock })
        let morpeko = Individual(baseID: 877, speciesID: 877, pathIDs: [877],
                                 nature: .hardy, obtainedAt: now, grade: .rare)
        store.mutate { s in
            s.box = [morpeko]
            s.partnerID = morpeko.id
            s.installBaselineSet = true
            s.lastDate = "2026-01-01"
        }
        store.update(todayTokens: 1_000, todayDate: "2026-01-01", hasUsageData: true)
        XCTAssertFalse(store.state.box[0].hangry, "방금 먹었는데 배고프다")

        // 델타 없이 시간만 흐른 틱 — 여기서 배고파져야 한다.
        clock = now.addingTimeInterval(BattleStateForm.hangryAfter + 60)
        store.update(todayTokens: 1_000, todayDate: "2026-01-01", hasUsageData: true)
        XCTAssertTrue(store.state.box[0].hangry, "30분이 지났는데 계속 배부르다")

        // 다시 토큰이 들어오면 배부름으로 돌아온다.
        store.update(todayTokens: 2_000, todayDate: "2026-01-01", hasUsageData: true)
        XCTAssertFalse(store.state.box[0].hangry, "먹었는데 배고픈 채로 남았다")
    }

    /// 배고픔 키가 없는 기존 세이브가 그대로 열린다(개체가 버려지면 안 된다).
    func testAnOldSaveWithoutHungerDecodes() throws {
        let json = Data(#"{"baseID":877,"speciesID":877,"nature":"hardy","grade":"rare"}"#.utf8)
        let decoded = try JSONDecoder().decode(Individual.self, from: json)
        XCTAssertFalse(decoded.hangry)
    }

    /// **도감은 이 모습들을 안 센다** — 상태이지 종이 아니다(메가·깨짐·히어로와 같은 규칙).
    func testTheseStatesNeverSplitTheDex() {
        var cram = cramorant(partner: true, stints: 0)
        cram.partnerSince = now
        XCTAssertEqual(DexKey.key(for: cram), "845")
        var morpeko = Individual(baseID: 877, speciesID: 877, pathIDs: [877],
                                 nature: .hardy, obtainedAt: now, grade: .rare)
        morpeko.hangry = true
        XCTAssertEqual(DexKey.key(for: morpeko), "877")
    }
}
