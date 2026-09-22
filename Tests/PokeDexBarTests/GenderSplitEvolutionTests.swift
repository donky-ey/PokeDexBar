import XCTest
@testable import PokeDexBar

/// 성별이 **갈래를 막는가, 폼을 가르는가.**
///
/// 사용자 제보: 맛보돈 암컷이 진화를 안 한다. 실제 응답을 전수로 보니 성별 값이 있는 갈래는
/// 아홉인데 그중 **셋은 암수 두 줄이 같은 자식 종을 가리킨다** — 제한이 아니라 폼이 갈리는
/// 것뿐이다(맛보돈·배쓰나이·냐스퍼). 셋 다 수컷 줄이 먼저라, "처음 만난 성별"을 제한으로 읽던
/// 예전 코드에서는 암컷이 전부 막혔다.
final class GenderSplitEvolutionTests: XCTestCase {

    private func detail(gender: Int?, level: Int) -> EvolutionDetail {
        EvolutionDetail(trigger: NamedRef(name: "level-up", url: nil), item: nil, held_item: nil,
                        min_happiness: nil, min_level: level, gender: gender,
                        base_form: nil, required_pokemon_form: nil)
    }

    /// evolution-chain 의 맛보돈 → 올리르바 두 줄. **응답 순서 그대로** 수컷이 먼저다.
    private var lechonk: [EvolutionDetail] { [detail(gender: 2, level: 18),
                                              detail(gender: 1, level: 18)] }

    /// **암수가 다 있으면 제한이 아니다.** 같은 자식 종으로 가는 두 줄이고, 갈리는 것은 폼이다.
    func testABranchBothGendersCanTakeHasNoRestriction() {
        XCTAssertNil(PokeAPIClient.gender(from: lechonk), "맛보돈 암컷이 막힌다")
    }

    /// 같은 성질의 나머지 둘 — 배쓰나이·냐스퍼도 응답에서 수컷 줄이 먼저다.
    func testTheOtherTwoFormSplitsAreAlsoUnrestricted() {
        let order = [detail(gender: 2, level: 1), detail(gender: 1, level: 1)]
        XCTAssertNil(PokeAPIClient.gender(from: order))
        // 줄 순서가 뒤집혀도 같은 답이어야 한다 — 순서에 기대면 다음 데이터 갱신에 또 뒤집힌다.
        XCTAssertNil(PokeAPIClient.gender(from: order.reversed()))
    }

    /// **진짜 제한은 그대로 남는다** — 대조군. 없으면 "성별을 늘 무시한다"도 통과하고,
    /// 그러면 수컷 눈꼬마가 눈여아가 된다.
    func testAGenuineSingleGenderGateStillHolds() {
        XCTAssertEqual(PokeAPIClient.gender(from: [detail(gender: 1, level: 42)]), .female)
        XCTAssertEqual(PokeAPIClient.gender(from: [detail(gender: 2, level: 30)]), .male)
    }

    /// 성별 줄과 성별 없는 줄이 섞이면 — 제한은 그 성별 하나다(도구+성별을 같이 요구하는 갈래).
    func testAGenderRowAmongPlainRowsStillRestricts() {
        XCTAssertEqual(PokeAPIClient.gender(from: [detail(gender: nil, level: 20),
                                                   detail(gender: 2, level: 20)]), .male)
    }

    func testNoGenderAtAllIsNoRestriction() {
        XCTAssertNil(PokeAPIClient.gender(from: [detail(gender: nil, level: 16)]))
        XCTAssertNil(PokeAPIClient.gender(from: nil))
        XCTAssertNil(PokeAPIClient.gender(from: []))
    }
}
