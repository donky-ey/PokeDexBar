import XCTest
@testable import PokeDexBar

/// 두 배 값 사다리 — 값·누적·상한.
final class DoublingLadderTests: XCTestCase {
    func testPricesDouble() {
        let ladder = DoublingLadder(base: 20)
        XCTAssertEqual(ladder.price(step: 1), 20)
        XCTAssertEqual(ladder.price(step: 2), 40)
        XCTAssertEqual(ladder.price(step: 3), 80)
        XCTAssertEqual(ladder.price(step: 4), 160)
    }

    /// 1단계 미만은 값이 없다 — 0 이나 음수를 값으로 돌려주면 공짜가 생긴다.
    func testStepsBelowOneHaveNoPrice() {
        let ladder = DoublingLadder(base: 20)
        XCTAssertNil(ladder.price(step: 0))
        XCTAssertNil(ladder.price(step: -1))
    }

    /// **상한은 base 에서 유도된다.** 손으로 적은 상한을 실제로 밟아 `Int` 곱셈 트랩으로
    /// 프로세스가 죽은 전례가 있다(`CharmLadder` 주석). base 가 크면 상한이 낮아야 한다.
    func testTheBoundFollowsTheBase() {
        XCTAssertGreaterThan(DoublingLadder(base: 20).maxStep,
                             DoublingLadder(base: 250_000_000).maxStep)
    }

    /// 상한 안의 모든 단계에서 값과 누적이 **실제로 넘치지 않는다** — 픽스처가 아니라
    /// 산술 자체에 물어본다.
    func testNothingOverflowsWithinTheBound() {
        for base in [1, 20, 250_000_000] {
            let ladder = DoublingLadder(base: base)
            for step in 1...ladder.maxStep {
                XCTAssertNotNil(ladder.price(step: step), "base \(base) step \(step)")
                XCTAssertGreaterThan(ladder.cumulative(through: step), 0, "base \(base) step \(step)")
            }
            XCTAssertNil(ladder.price(step: ladder.maxStep + 1), "상한 밖인데 값이 있다")
        }
    }

    func testCumulativeIsTheSumOfEveryStep() {
        let ladder = DoublingLadder(base: 20)
        XCTAssertEqual(ladder.cumulative(through: 0), 0)
        XCTAssertEqual(ladder.cumulative(through: 3), 20 + 40 + 80)
    }
}
