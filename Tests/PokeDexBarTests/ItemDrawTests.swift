import XCTest
@testable import PokeDexBar

/// 박사의 상자 — 확률표·사다리·하루 경계.
@MainActor
final class ItemDrawTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeStore(now: @escaping () -> Date) -> PlayerStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("itemdraw-\(UUID().uuidString).json")
        return PlayerStore(fileURL: url, rng: SeededRNG(seed: 11), now: now)
    }

    // MARK: 확률표

    /// 천분율 합이 정확히 1000. 어긋나면 마지막 상품이 새거나 굴림이 표 밖으로 나간다.
    func testTheWeightsSumToExactlyOneThousand() {
        XCTAssertEqual(ItemDrawBalance.pool.reduce(0) { $0 + $1.weight }, 1000)
    }

    func testEveryWeightIsPositive() {
        for entry in ItemDrawBalance.pool {
            XCTAssertGreaterThan(entry.weight, 0, "\(entry.prize)")
        }
    }

    /// 표의 모든 상품이 **실제로 나온다** — 정수 공간 누적이 마지막 항목을 안 흘리는지.
    func testEveryPrizeIsReachable() {
        var seen = Set<String>()
        for step in 0..<10_000 {
            seen.insert(String(describing: ItemDrawBalance.roll(Double(step) / 10_000).prize))
        }
        XCTAssertEqual(seen.count, ItemDrawBalance.pool.count,
                       "도달 못 한 상품이 있다: \(seen)")
    }

    /// 경계 바로 위아래가 서로 다른 상품이다 — 소수 누적이었으면 여기서 샌다.
    func testTheRollNeverFallsOffTheEnd() {
        XCTAssertNotNil(ItemDrawBalance.roll(0.9999).prize)
        XCTAssertNotNil(ItemDrawBalance.roll(1.0).prize)
        XCTAssertNotNil(ItemDrawBalance.roll(0.0).prize)
    }

    /// **반짝이는 사탕은 풀에 없다.** 게임 전체를 통틀어 2개라는 기록된 결정을 잠근다
    /// (`DexMissions.all` 주석). 매일 도는 뽑기에 넣으면 그 결정이 무효가 된다.
    func testShinyCandyIsNotInThePool() {
        for entry in ItemDrawBalance.pool {
            if case .item(let item, _) = entry.prize {
                XCTAssertNotEqual(item, .shinyCandy, "반짝사탕이 뽑기에 들어갔다")
            }
        }
    }

    // MARK: 값 사다리

    func testTheFirstDrawOfTheDayIsFree() {
        let store = makeStore(now: { self.now })
        store.seedForTesting(wallet: 0, slots: 3, eggs: 0, at: now)
        XCTAssertTrue(store.itemDrawIsFree)
        XCTAssertNotNil(store.drawItem(), "포인트가 0인데 무료 판이 안 돌았다")
        XCTAssertFalse(store.itemDrawIsFree)
    }

    func testThePriceDoublesWithinTheDay() {
        let store = makeStore(now: { self.now })
        store.seedForTesting(wallet: 0, slots: 3, eggs: 0, at: now)
        store.grantPointsForTesting(1000)
        _ = store.drawItem()                       // 무료 한 판
        XCTAssertEqual(store.nextItemDrawPrice, 20)
        _ = store.drawItem()
        XCTAssertEqual(store.nextItemDrawPrice, 40)
        _ = store.drawItem()
        XCTAssertEqual(store.nextItemDrawPrice, 80)
    }

    /// 포인트가 모자라면 **nil 이고 아무것도 안 줄어든다.** 제안 데려오기와 같은 규칙이다.
    func testAShortWalletDeductsNothing() {
        let store = makeStore(now: { self.now })
        store.seedForTesting(wallet: 0, slots: 3, eggs: 0, at: now)
        store.grantPointsForTesting(5)
        _ = store.drawItem()                       // 무료 한 판
        let before = store.state.researchPoints
        XCTAssertNil(store.drawItem(), "5점으로 20점짜리를 뽑았다")
        XCTAssertEqual(store.state.researchPoints, before)
        XCTAssertEqual(store.state.paidItemDraws, 0, "실패한 판이 세어졌다")
    }

    func testAPaidDrawDeductsExactlyThePrice() {
        let store = makeStore(now: { self.now })
        store.seedForTesting(wallet: 0, slots: 3, eggs: 0, at: now)
        store.grantPointsForTesting(100)
        _ = store.drawItem()                       // 무료
        XCTAssertNotNil(store.drawItem())          // 20점
        XCTAssertEqual(store.state.researchPoints, 80)
    }

    /// 뽑은 것이 **실제로 가방에 들어간다** — 차감만 되고 물건이 없으면 안 된다.
    func testThePrizeLandsInTheBag() {
        let store = makeStore(now: { self.now })
        store.seedForTesting(wallet: 0, slots: 3, eggs: 0, at: now)
        let result = store.drawItem()
        let prize = try! XCTUnwrap(result)
        XCTAssertGreaterThanOrEqual(store.count(of: prize.item), prize.count)
    }

    // MARK: 하루 경계

    /// 날짜가 바뀌면 무료와 유료 카운터가 **둘 다** 초기화된다. 하나만 비면 값이 안 내려간다.
    func testTheDayRolloverResetsBothCounters() {
        var clock = now
        let store = makeStore(now: { clock })
        store.seedForTesting(wallet: 0, slots: 3, eggs: 0, at: clock)
        store.update(todayTokens: 0, todayDate: "2023-11-14", hasUsageData: true)   // 기준선
        store.grantPointsForTesting(1000)
        _ = store.drawItem()
        _ = store.drawItem()
        XCTAssertFalse(store.itemDrawIsFree)
        XCTAssertEqual(store.state.paidItemDraws, 1)

        clock = now.addingTimeInterval(86_400)
        store.update(todayTokens: 0, todayDate: "2023-11-15", hasUsageData: true)
        XCTAssertTrue(store.itemDrawIsFree, "다음 날인데 무료가 안 돌아왔다")
        XCTAssertEqual(store.state.paidItemDraws, 0, "다음 날인데 값이 안 내려갔다")
    }

    /// 초기화가 **하루 경계 그 한 곳**에서 일어난다. 판정이 두 곳이면 반드시 갈린다.
    func testTheResetLivesWithTheOtherDailyLedgers() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/PokeDexBar/Player/PlayerStore.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        // 주석을 먼저 걷어낸다 — 통짜 검색은 바로 위 주석의 같은 낱말에 걸려, 코드를 지워도 통과한다.
        let code = source.split(separator: "\n")
            .map { $0.contains("//") ? String($0[..<$0.range(of: "//")!.lowerBound]) : String($0) }
            .joined(separator: "\n")
        XCTAssertTrue(code.contains("freeItemDrawUsed = false"), "무료권 초기화가 없다")
        XCTAssertTrue(code.contains("paidItemDraws = 0"), "유료 카운터 초기화가 없다")
    }

    // MARK: 경계 검증

    /// 봉인이 깨진 세이브의 큰 값이 `1 << n` 에 들어가면 오버플로 트랩으로 프로세스가 죽는다.
    func testATamperedCounterIsClamped() throws {
        let state = try PlayerStateFixture.decoded(paidItemDraws: Int.max)
        XCTAssertLessThanOrEqual(state.paidItemDraws, ItemDrawBalance.ladder.maxStep)
        XCTAssertGreaterThanOrEqual(state.paidItemDraws, 0)
        let negative = try PlayerStateFixture.decoded(paidItemDraws: -5)
        XCTAssertEqual(negative.paidItemDraws, 0)
    }

    /// 세대권이 나왔을 때 아홉 세대가 전부 도달 가능하다 — `% 9` 류의 off-by-one 이면
    /// 한 세대가 영영 안 나온다.
    func testEveryGenerationCanBeDrawn() {
        var seen = Set<Int>()
        for seed in 0..<400 {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("gen-\(UUID().uuidString).json")
            let store = PlayerStore(fileURL: url, rng: SeededRNG(seed: UInt64(seed)),
                                    now: { self.now })
            store.seedForTesting(wallet: 0, slots: 3, eggs: 0, at: now)
            store.grantPointsForTesting(10_000)
            for _ in 0..<6 {
                if let result = store.drawItem(), let g = result.item.guaranteedGeneration {
                    seen.insert(g)
                }
            }
        }
        XCTAssertEqual(seen, Set(1...9), "안 나오는 세대가 있다: \(Set(1...9).subtracting(seen))")
    }
}
