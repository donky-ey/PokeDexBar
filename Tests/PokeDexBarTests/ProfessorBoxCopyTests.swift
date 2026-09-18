import XCTest
@testable import PokeDexBar

/// 박사의 상자 문구 — 확률 줄·버튼 값·각주.
///
/// 사용자 지적: "모르는 사람은 그냥 연타해서 뽑겠어. 이게 무슨 기능인지, 확률이 얼마인지,
/// 이번에 얼마 주고 뽑아야 하는지를 확실하게 보여줘." 세 가지가 각각 테스트로 잠긴다.
@MainActor
final class ProfessorBoxCopyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeStore() -> PlayerStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("boxcopy-\(UUID().uuidString).json")
        let store = PlayerStore(fileURL: url, rng: SeededRNG(seed: 5), now: { self.now })
        store.seedForTesting(wallet: 0, slots: 3, eggs: 0, at: now)
        return store
    }

    // MARK: 확률 줄 — 무엇이 들어 있고 얼마나 나오나

    /// **표에서 유도된다.** 손으로 적으면 가중치를 고칠 때 문구가 조용히 거짓이 된다 —
    /// 알 뽑기의 `EggSlotsView.oddsText` 가 `EggBalance.odds` 에서 유도하는 것과 같은 이유다.
    func testTheOddsLineNamesEveryPrizeInThePool() {
        let text = ItemDrawBalance.oddsText(.ko)
        for entry in ItemDrawBalance.pool {
            let name = ItemDrawBalance.prizeName(entry.prize, .ko)
            XCTAssertTrue(text.contains(name), "\(name) 이 확률 줄에 없다: \(text)")
        }
    }

    /// 천분율이 소수 한 자리까지 정확히 떨어진다 — 45‰ 는 4%가 아니라 **4.5%** 다.
    /// 자르면 에픽·레전더리가 실제보다 낮게 적힌다.
    func testFractionalOddsKeepTheirDecimal() {
        let text = ItemDrawBalance.oddsText(.ko)
        XCTAssertTrue(text.contains("4.5%"), "에픽이 4%로 잘렸다: \(text)")
        XCTAssertTrue(text.contains("1.5%"), "레전더리가 1%로 잘렸다: \(text)")
        XCTAssertTrue(text.contains("34%"), "정수 확률에 불필요한 소수가 붙었다: \(text)")
        XCTAssertFalse(text.contains("34.0%"), "정수 확률에 .0 이 붙었다: \(text)")
    }

    /// 적힌 확률의 합이 100% 다 — 하나라도 빠지거나 겹치면 여기서 걸린다.
    func testTheOddsInTheLineAddUpToOneHundred() {
        let percents = ItemDrawBalance.pool.map { Double($0.weight) / 10 }
        XCTAssertEqual(percents.reduce(0, +), 100, accuracy: 0.001)
    }

    /// 세 언어 모두에서 비어 있지 않고, 서로 다르다(번역이 실제로 붙었는지).
    func testTheOddsLineIsWrittenInEveryLanguage() {
        let texts = [AppLanguage.ko, .en, .ja].map { ItemDrawBalance.oddsText($0) }
        for text in texts { XCTAssertFalse(text.isEmpty) }
        XCTAssertEqual(Set(texts).count, 3, "언어별로 같은 문구가 나온다: \(texts)")
    }

    // MARK: 버튼 — 이번 판에 얼마

    /// 값이 **버튼 위에** 있어야 한다. 각주에 두면 누르는 곳과 치르는 값이 떨어져 있다.
    func testTheButtonCarriesThisDrawsPrice() {
        let store = makeStore()
        XCTAssertEqual(ProfessorBoxSection.buttonTitle(store: store), store.l.itemDrawButtonFree)

        store.grantPointsForTesting(1000)
        _ = store.drawItem()                       // 무료 소진
        XCTAssertEqual(ProfessorBoxSection.buttonTitle(store: store),
                       store.l.itemDrawButtonPriced(20))
        _ = store.drawItem()
        XCTAssertEqual(ProfessorBoxSection.buttonTitle(store: store),
                       store.l.itemDrawButtonPriced(40))
    }

    /// 값이 모자라도 **값은 그대로 보인다** — 얼마가 필요한지 알아야 기다릴 수 있다.
    func testThePriceStaysOnTheButtonWhenYouCannotAfford() {
        let store = makeStore()
        _ = store.drawItem()                       // 무료 소진, 포인트 0
        XCTAssertFalse(store.canDrawItem)
        XCTAssertEqual(ProfessorBoxSection.buttonTitle(store: store),
                       store.l.itemDrawButtonPriced(20))
    }

    // MARK: 각주 — 사다리를 미리 말한다

    /// **뽑기 전에** 값이 두 배씩 오른다는 것을 말해야 한다. 첫 판이 무료라고만 하면
    /// 연타하다가 세 번째에 40P 가 나가는 것을 뒤늦게 안다(사용자 지적).
    func testTheFootnoteWarnsAboutTheLadderBeforeTheFirstDraw() {
        let store = makeStore()
        store.grantPointsForTesting(1000)
        XCTAssertTrue(store.itemDrawIsFree)
        XCTAssertEqual(ProfessorBoxSection.footnote(store: store), store.l.itemDrawLadder(20))
    }

    /// 뽑고 나면 **그다음** 값을 말한다 — 지금 값이 아니라.
    func testTheFootnoteNamesThePriceAfterThisOne() {
        let store = makeStore()
        store.grantPointsForTesting(1000)
        _ = store.drawItem()                       // 무료
        XCTAssertEqual(ProfessorBoxSection.footnote(store: store), store.l.itemDrawLadder(40))
        _ = store.drawItem()                       // 20P
        XCTAssertEqual(ProfessorBoxSection.footnote(store: store), store.l.itemDrawLadder(80))
    }

    /// 못 누를 때는 사다리가 아니라 **이유**가 온다 — 대조군. 없으면 "늘 사다리만 낸다"도 통과한다.
    func testABlockedDrawSaysWhyInsteadOfTheLadder() {
        let store = makeStore()
        _ = store.drawItem()                       // 무료 소진, 포인트 0
        XCTAssertEqual(ProfessorBoxSection.footnote(store: store), store.l.itemDrawNeedsPoints(20))
    }
}
