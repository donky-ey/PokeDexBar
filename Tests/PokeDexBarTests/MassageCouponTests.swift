import XCTest
@testable import PokeDexBar

/// 마사지 쿠폰 — 한 마리의 친밀도를 24시간 늘린다.
@MainActor
final class MassageCouponTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeStore() -> PlayerStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("massage-\(UUID().uuidString).json")
        return PlayerStore(fileURL: url, rng: SeededRNG(seed: 7), now: { self.now })
    }

    private func pokemon(_ speciesID: Int) -> Individual {
        Individual(baseID: speciesID, speciesID: speciesID, pathIDs: [speciesID],
                   nature: .hardy, obtainedAt: now, grade: .common)
    }

    func testTheCouponAddsADayOfFriendship() {
        let store = makeStore()
        let eevee = pokemon(133)
        store.addForTesting(eevee)
        store.grantForTesting(.massageCoupon, count: 1)

        XCTAssertTrue(store.useMassageCoupon(on: eevee.id))
        XCTAssertEqual(store.state.box.first?.pettedSeconds, 86_400)
        XCTAssertEqual(store.count(of: .massageCoupon), 0, "쿠폰이 안 없어졌다")
    }

    /// **`partnerSeconds` 가 아니라 `pettedSeconds` 다.** 파트너 시간에 더하면 화면의
    /// "함께한 시간" 까지 늘어 실제로 곁에 있던 시간을 거짓으로 말하게 된다(기록된 사용자 지적).
    func testTheCouponDoesNotFakeTimeSpentTogether() {
        let store = makeStore()
        let eevee = pokemon(133)
        store.addForTesting(eevee)
        store.grantForTesting(.massageCoupon, count: 1)
        _ = store.useMassageCoupon(on: eevee.id)
        XCTAssertEqual(store.state.box.first?.partnerSeconds, 0)
    }

    /// 쓴 아이만 오른다 — 대조군이 없으면 "박스 전체에 더한다" 도 통과한다.
    func testOnlyTheChosenPokemonChanges() {
        let store = makeStore()
        let eevee = pokemon(133)
        let pikachu = pokemon(25)
        store.addForTesting(eevee)
        store.addForTesting(pikachu)
        store.grantForTesting(.massageCoupon, count: 1)

        _ = store.useMassageCoupon(on: eevee.id)
        XCTAssertEqual(store.state.box.first(where: { $0.id == pikachu.id })?.pettedSeconds, 0)
    }

    /// 한 장이 친밀도 진화 문턱을 **실제로** 넘긴다 — 숫자만 맞추고 문턱을 못 넘으면
    /// 이 아이템은 아무 일도 안 하는 셈이다.
    func testOneCouponCrossesTheFriendshipThreshold() {
        let store = makeStore()
        let eevee = pokemon(133)
        store.addForTesting(eevee)
        store.grantForTesting(.massageCoupon, count: 1)

        let before = store.state.box.first!.bondDuration(at: now)
        XCTAssertLessThan(before, EvoRequirement.friendshipSeconds, "쓰기 전에 이미 넘었다")
        _ = store.useMassageCoupon(on: eevee.id)
        let after = store.state.box.first!.bondDuration(at: now)
        XCTAssertGreaterThanOrEqual(after, EvoRequirement.friendshipSeconds)
    }

    /// 재고가 없으면 실패하고 **개체도 안 변한다** — 실패 경로가 상태를 남기면 안 된다.
    func testWithoutACouponNothingHappens() {
        let store = makeStore()
        let eevee = pokemon(133)
        store.addForTesting(eevee)

        XCTAssertFalse(store.useMassageCoupon(on: eevee.id))
        XCTAssertEqual(store.state.box.first?.pettedSeconds, 0)
    }

    /// 박스에 없는 id 면 실패하고 쿠폰도 안 없어진다.
    func testAnUnknownPokemonDoesNotBurnTheCoupon() {
        let store = makeStore()
        store.grantForTesting(.massageCoupon, count: 1)
        XCTAssertFalse(store.useMassageCoupon(on: UUID()))
        XCTAssertEqual(store.count(of: .massageCoupon), 1)
    }

    /// 쿠폰 값과 진화 문턱이 같은 값이라는 것을 못 박는다 — 한쪽만 바뀌면 "한 장이면 된다" 가
    /// 조용히 거짓이 된다.
    func testTheCouponMatchesTheFriendshipThreshold() {
        XCTAssertEqual(ItemDrawBalance.massageSeconds, EvoRequirement.friendshipSeconds)
    }
}
