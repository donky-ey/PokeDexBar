import XCTest
@testable import PokeDexBar

/// 지방 모습 줄을 **응답의 어느 필드로 가려내는가.**
///
/// 사용자 제보: 기본 야도란이 가라두구팔찌(갈라르 조건)를 요구한다. 조사해 보니 `base_form` 은
/// 전 540체인 576줄에서 **전부 null** 이고, 줄의 주인은 `required_pokemon_form` 에만 적혀 있다.
/// 그래서 `isRegional` 이 한 번도 참이 된 적이 없고, 지방 조건이 전부 원종으로 샜다.
///
/// 아래 픽스처는 **실제 응답에서 잘라 온 것**이다(evolution-chain/33). 손으로 쓴 픽스처가
/// 파서와 같은 오해를 공유해 둘 다 틀린 채로 통과한 것이 이 결함의 발생 경위다.
final class RegionalFormFieldTests: XCTestCase {

    /// evolution-chain/33 의 야돈 → 야도란 두 줄. `base_form` 은 **응답 그대로 nil** 이다.
    private var slowpokeToSlowbro: [EvolutionDetail] {
        [
            // red-blue: 레벨 37 (관동)
            EvolutionDetail(trigger: NamedRef(name: "level-up", url: nil), item: nil,
                            held_item: nil, min_happiness: nil, min_level: 37, gender: nil,
                            base_form: nil,
                            required_pokemon_form: nil),
            // the-isle-of-armor: 가라두구팔찌 (갈라르)
            EvolutionDetail(trigger: NamedRef(name: "use-item", url: nil),
                            item: NamedRef(name: "galarica-cuff", url: nil),
                            held_item: nil, min_happiness: nil, min_level: nil, gender: nil,
                            base_form: nil,
                            required_pokemon_form: NamedRef(name: "slowpoke-galar", url: nil)),
        ]
    }

    /// **기본 야도란은 레벨 37이다.** 갈라르 줄이 안 걸러지면 "도구가 레벨보다 우선" 규칙에
    /// 걸려 가라두구팔찌가 원종의 조건이 된다 — 사용자가 본 그 화면이다.
    func testTheKantonianSlowbroWantsALevelNotTheGalaricaCuff() {
        let requirement = PokeAPIClient.requirement(from: slowpokeToSlowbro,
                                                    speciesID: 80, parentLevel: 1)
        XCTAssertEqual(requirement, .level(37), "관동 야도란이 갈라르 조건을 물려받았다")
    }

    /// 갈라르 쪽은 그 조건을 그대로 갖는다 — 갈라내는 것이지 버리는 것이 아니다.
    func testTheGalarianSlowbroKeepsTheCuff() {
        XCTAssertEqual(PokeAPIClient.regionalRequirement(from: slowpokeToSlowbro),
                       .item("galarica-cuff"))
    }

    /// 줄의 주인은 `required_pokemon_form` 으로 가린다.
    func testTheOwnerIsReadFromRequiredPokemonForm() {
        XCTAssertTrue(PokeAPIClient.isRegional(slowpokeToSlowbro[1]))
        XCTAssertFalse(PokeAPIClient.isRegional(slowpokeToSlowbro[0]))
    }

    /// **값이 있다고 지방이 아니다.** 이 필드에는 폼 조건이 두루 오는데, 실제 응답에서 가장 많은
    /// 것은 이브이(19줄)이고 그 값은 *원종 자신*을 가리킨다. 유무로 가르면 이브이가 조건을
    /// 통째로 잃는다 — 판정은 지방 접미사여야 한다.
    func testAFormGateThatIsNotRegionalStaysWithTheBaseForm() {
        let eevee = EvolutionDetail(trigger: NamedRef(name: "use-item", url: nil),
                                    item: NamedRef(name: "water-stone", url: nil),
                                    held_item: nil, min_happiness: nil, min_level: nil,
                                    gender: nil, base_form: nil,
                                    required_pokemon_form: NamedRef(name: "eevee", url: nil))
        XCTAssertFalse(PokeAPIClient.isRegional(eevee), "이브이 줄을 지방으로 봤다")
        XCTAssertEqual(PokeAPIClient.requirement(from: [eevee], speciesID: 134, parentLevel: 1),
                       .item("water-stone"))
    }

    /// 네 지방 접미사가 모두 잡힌다 — 실제 응답에 있는 값들이다.
    func testEveryRegionSuffixIsRecognised() {
        for slug in ["vulpix-alola", "slowpoke-galar", "growlithe-hisui", "wooper-paldea"] {
            let detail = EvolutionDetail(trigger: nil, item: nil, held_item: nil,
                                         min_happiness: nil, min_level: 5, gender: nil,
                                         base_form: nil,
                                         required_pokemon_form: NamedRef(name: slug, url: nil))
            XCTAssertTrue(PokeAPIClient.isRegional(detail), slug)
        }
    }
}
