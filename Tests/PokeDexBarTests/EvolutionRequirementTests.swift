import XCTest
@testable import PokeDexBar

/// PokéAPI 진화 조건 파싱 — 실제 응답 모양 그대로 만든 픽스처로 잰다.
final class EvolutionRequirementTests: XCTestCase {

    private func detail(_ json: String) throws -> EvolutionDetail {
        try JSONDecoder().decode(EvolutionDetail.self, from: Data(json.utf8))
    }

    /// 표에 없는 종 — 카탈로그가 끼어들지 않는다는 걸 보장하려고 고정으로 쓴다.
    private let uncatalogued = 4   // 파이리 — PokéAPI 가 레벨을 준다

    /// `min_level` 을 읽는다 — 파이리는 16레벨.
    func testAStatedLevelIsUsedAsIs() throws {
        let d = try detail(#"{"trigger":{"name":"level-up","url":null},"min_level":16}"#)
        XCTAssertEqual(PokeAPIClient.requirement(from: [d], speciesID: uncatalogued, parentLevel: 1), .level(16))
    }

    /// **우선순위는 안 바뀐다** — 도구가 있으면 레벨보다 도구다.
    func testAnItemStillWinsOverALevel() throws {
        let d = try detail(#"""
        {"trigger":{"name":"level-up","url":null},"min_level":30,"item":{"name":"fire-stone","url":null}}
        """#)
        XCTAssertEqual(PokeAPIClient.requirement(from: [d], speciesID: uncatalogued, parentLevel: 1), .item("fire-stone"))
    }

    /// **관동 나옹은 레벨 28이지 친밀도가 아니다**(사용자 지적). 친밀도는 알로라 나옹의
    /// 조건인데, 응답이 두 줄을 한 갈래에 담아 보낸다 — 모래두지와 같은 부류다.
    /// 아래는 실제 응답에서 그대로 잘라낸 두 줄이다(`base_form` 포함).
    func testKantonianMeowthEvolvesByLevelNotFriendship() throws {
        let kanto = try detail(#"""
        {"version_group":{"name":"red-blue","url":null},"is_default":true,
         "trigger":{"name":"level-up","url":null},"min_level":28}
        """#)
        let alola = try detail(#"""
        {"version_group":{"name":"sun-moon","url":null},"is_default":true,
         "trigger":{"name":"level-up","url":null},"min_happiness":160,
         "base_form":{"name":"meowth-alola","url":null},
         "evolved_form":{"name":"persian-alola","url":null}}
        """#)
        XCTAssertEqual(PokeAPIClient.requirement(from: [kanto, alola], speciesID: 52, parentLevel: 1),
                       .level(28), "알로라의 친밀도가 관동의 레벨을 가로챘다")
        XCTAssertEqual(PokeAPIClient.regionalRequirement(from: [kanto, alola]), .friendship,
                       "알로라 나옹의 친밀도 조건이 사라졌다")
    }

    /// **부류 스윕** — 나옹과 같은 모양이 셋 더 있었다(전 484갈래 전수 비교). 지방 조건이
    /// 비어 있어서 지방 모습이 *원종의* 조건을 물려받고 있었다: 알로라 식스테일은 불의돌을,
    /// 갈라르 야도킹은 왕의징표석을 요구했다. 셋 다 원작에 없는 조건이다.
    func testRegionalFormsKeepTheirOwnCondition() throws {
        // 로코온 — 원종은 불의돌, 알로라는 얼음의돌.
        let vulpixKanto = try detail(#"""
        {"trigger":{"name":"use-item","url":null},"item":{"name":"fire-stone","url":null}}
        """#)
        let vulpixAlola = try detail(#"""
        {"trigger":{"name":"use-item","url":null},"item":{"name":"ice-stone","url":null},
         "base_form":{"name":"vulpix-alola","url":null}}
        """#)
        XCTAssertEqual(PokeAPIClient.requirement(from: [vulpixKanto, vulpixAlola],
                                                 speciesID: 37, parentLevel: 1), .item("fire-stone"))
        XCTAssertEqual(PokeAPIClient.regionalRequirement(from: [vulpixKanto, vulpixAlola]),
                       .item("ice-stone"), "알로라 식스테일이 불의돌을 요구한다")

        // 야도란 — 원종은 왕의징표석 교환, 갈라르는 가라르화관. **든 도구라 예전 규칙이 못 봤다.**
        let slowKanto = try detail(#"""
        {"trigger":{"name":"trade","url":null},"held_item":{"name":"kings-rock","url":null}}
        """#)
        let slowGalar = try detail(#"""
        {"trigger":{"name":"use-item","url":null},"item":{"name":"galarica-wreath","url":null},
         "base_form":{"name":"slowpoke-galar","url":null}}
        """#)
        XCTAssertEqual(PokeAPIClient.regionalRequirement(from: [slowKanto, slowGalar]),
                       .item("galarica-wreath"), "갈라르 야도킹이 왕의징표석을 요구한다")
    }

    /// 지방 모습의 조건이 **든 도구**일 수도 있다 — 히스이 포푸니라는 예리한손톱을 들고 오른다.
    /// `item` 만 보면 이 갈래가 조건 없이 지나간다.
    func testARegionalHeldItemIsReadToo() throws {
        let hisui = try detail(#"""
        {"trigger":{"name":"level-up","url":null},"held_item":{"name":"razor-claw","url":null},
         "base_form":{"name":"sneasel-hisui","url":null}}
        """#)
        XCTAssertEqual(PokeAPIClient.regionalRequirement(from: [hisui]), .item("razor-claw"))
    }

    /// **지방 줄만 있는 갈래는 그 줄을 원종 조건으로도 쓴다.** 가라르 나옹만 나이킹이 되므로
    /// 응답에 원종 줄이 아예 없다 — 갈라내고 끝내면 남는 줄이 0개가 되어 레벨 28이 사라지고
    /// 지어낸 레벨로 떨어진다. 창치(칼모짱)·마임꽁꽁 등 열 갈래가 같은 모양이다.
    func testABranchWithOnlyRegionalRowsStillKeepsItsCondition() throws {
        let galar = try detail(#"""
        {"trigger":{"name":"level-up","url":null},"min_level":28,
         "base_form":{"name":"meowth-galar","url":null}}
        """#)
        XCTAssertEqual(PokeAPIClient.requirement(from: [galar], speciesID: 863, parentLevel: 1),
                       .level(28), "지방 줄만 있는 갈래가 조건을 잃었다")
    }

    /// **`base_form` 이 있다고 지방 모습이 아니다** — 대조군. 이브이의 여덟 갈래는 전부
    /// `base_form: eevee`(원종 자신)라, 값의 유무로 가르면 이브이가 조건을 통째로 잃는다.
    /// 전수 확인에서 22갈래가 이 모양이었다(이브이·피카츄·플라베베·루가루암·호루비·바스라오).
    func testABaseFormNamingTheOriginalIsNotRegional() throws {
        let espeon = try detail(#"""
        {"trigger":{"name":"level-up","url":null},"min_happiness":160,
         "base_form":{"name":"eevee","url":null}}
        """#)
        XCTAssertFalse(PokeAPIClient.isRegional(espeon))
        XCTAssertEqual(PokeAPIClient.requirement(from: [espeon], speciesID: 133, parentLevel: 1),
                       .friendship, "이브이가 자기 조건을 잃었다")
        XCTAssertNil(PokeAPIClient.regionalRequirement(from: [espeon]))
    }

    /// 친밀도도 레벨보다 앞선다.
    func testFriendshipStillWinsOverALevel() throws {
        let d = try detail(#"{"trigger":{"name":"level-up","url":null},"min_level":30,"min_happiness":160}"#)
        XCTAssertEqual(PokeAPIClient.requirement(from: [d], speciesID: uncatalogued, parentLevel: 1), .friendship)
    }

    /// **든 도구도 도구다.** 럭키·포푸니라·글라이온·포푸니크 넷이 여기 걸린다 —
    /// 지금까지는 통신교환일 때만 `held_item` 을 봤다. 원작의 시간대 조건은 버린다.
    func testAHeldItemOnLevelUpCountsAsAnItem() throws {
        let d = try detail(#"""
        {"trigger":{"name":"level-up","url":null},"held_item":{"name":"razor-claw","url":null},
         "time_of_day":"night"}
        """#)
        XCTAssertEqual(PokeAPIClient.requirement(from: [d], speciesID: uncatalogued, parentLevel: 1), .item("razor-claw"))
    }

    /// 통신교환은 지금 그대로 — 든 물건이 있으면 그 물건, 없으면 연결의 끈.
    func testTradeIsUnchanged() throws {
        let plain = try detail(#"{"trigger":{"name":"trade","url":null}}"#)
        XCTAssertEqual(PokeAPIClient.requirement(from: [plain], speciesID: uncatalogued, parentLevel: 1), .item("linking-cord"))
        let held = try detail(#"""
        {"trigger":{"name":"trade","url":null},"held_item":{"name":"metal-coat","url":null}}
        """#)
        XCTAssertEqual(PokeAPIClient.requirement(from: [held], speciesID: uncatalogued, parentLevel: 1), .item("metal-coat"))
    }

    /// **레벨이 안 적힌 갈래는 `max(앞 단계 + 8, 20)`.**
    /// 앞 단계가 알에서 나오면(레벨 1) 20이고, 늦게 오는 앞 단계에서는 그 위로 밀린다.
    /// **카탈로그에 없는 종으로 고정한다** — 983(대도각참)처럼 카탈로그에 있는 종을 쓰면
    /// 규칙값과 카탈로그값이 우연히 같아져 폴백이 실제로 도는지 구분이 안 된다.
    func testAnUnstatedLevelFallsBackToTheRule() throws {
        let d = try detail(#"{"trigger":{"name":"spin","url":null}}"#)
        XCTAssertEqual(PokeAPIClient.requirement(from: [d], speciesID: uncatalogued, parentLevel: 1), .level(20))
        XCTAssertEqual(PokeAPIClient.requirement(from: [d], speciesID: uncatalogued, parentLevel: 52), .level(60))
        XCTAssertEqual(PokeAPIClient.requirement(from: [d], speciesID: uncatalogued, parentLevel: 33), .level(41))
    }

    /// 뿌리(조건 목록 자체가 없음)는 `.none` 이다.
    func testTheRootHasNoRequirement() {
        XCTAssertEqual(PokeAPIClient.requirement(from: nil, speciesID: uncatalogued, parentLevel: 1), .none)
        XCTAssertEqual(PokeAPIClient.requirement(from: [], speciesID: uncatalogued, parentLevel: 1), .none)
    }

    /// 새 도구 셋이 카탈로그에 있다 — 없으면 위 `held_item` 규칙이 조건 없음으로 샌다.
    func testTheThreeNewItemsExist() {
        XCTAssertNotNil(EvolutionItem.named("oval-stone"))
        XCTAssertNotNil(EvolutionItem.named("razor-claw"))
        XCTAssertNotNil(EvolutionItem.named("razor-fang"))
    }

    /// 성장 타입이 종 응답에서 실린다.
    func testGrowthRateComesFromTheSpeciesResponse() throws {
        let json = #"""
        {"capture_rate":45,"is_legendary":false,"is_mythical":false,"names":[],
         "evolution_chain":{"url":"https://pokeapi.co/api/v2/evolution-chain/2/"},
         "evolves_from_species":null,"growth_rate":{"name":"medium-slow","url":null},
         "gender_rate":4}
        """#
        let dto = try JSONDecoder().decode(SpeciesDTO.self, from: Data(json.utf8))
        XCTAssertEqual(GrowthRate.fromAPI(dto.growth_rate.name), .mediumSlow)
    }
}
