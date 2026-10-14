import XCTest
@testable import PokeDexBar

/// 진화 도구 41종 — **전부 리본 파트너가 물어 오고, 재화로는 못 산다.** 규칙이 하나여야 한다는
/// 게 요점이다: 돌만 상점에 두면 "똑같이 며칠 걸려 얻었는데 돌만 사라지는" 모순이 생긴다.
final class EvolutionItemCatalogTests: XCTestCase {
    /// **모든 도구가 채집으로 얻어져야 한다.** 상점이 없으므로 표에서 빠진 도구는 영영 못 얻고,
    /// 그 도구를 요구하는 진화는 영영 막힌다 — 이 앱에서 가장 조용히 번지는 결함 유형이다.
    func testEveryItemIsObtainableByForaging() {
        let obtainable = Set(ForageCatalog.bySpecies.values.flatMap { $0 }.map(\.item))
        for item in EvolutionItem.allCases {
            XCTAssertTrue(obtainable.contains(item), "\(item) 을 물어 오는 종이 없다 — 영영 못 얻는다")
        }
    }

    /// 반대 방향 — 표에 있는 도구는 전부 enum 에 있어야 한다(타입이 보장하지만 개수로도 확인).
    func testCatalogAndEnumAgreeOnTheItemSet() {
        let obtainable = Set(ForageCatalog.bySpecies.values.flatMap { $0 }.map(\.item))
        XCTAssertEqual(obtainable.count, EvolutionItem.allCases.count)
    }

    /// 재화로 사는 길이 없어야 한다 — 상점 경로가 되살아나면 리본이 할 일이 없어진다.
    /// `ShopItem` 은 사는 것, `EvolutionItem` 은 모으는 것으로 갈라 둔 게 그 방어다.
    func testEvolutionItemsAreNotShopItems() {
        let shopKeys = Set(ShopItem.allCases.map(\.rawValue))
        for item in EvolutionItem.allCases {
            XCTAssertFalse(shopKeys.contains(item.rawValue),
                           "\(item) 이 상점 품목과 키가 겹친다 — 인벤토리가 한 칸을 두고 다툰다")
        }
    }

    /// PokéAPI 이름으로 찾을 수 있어야 한다 — 못 찾으면 그 진화가 조건 없이 열려 버린다.
    func testLookupByAPIName() {
        XCTAssertEqual(EvolutionItem.named("water-stone"), .waterStone)
        XCTAssertEqual(EvolutionItem.named("black-augurite"), .blackAugurite)
        XCTAssertNil(EvolutionItem.named("rare-candy"))
    }
}

/// 조건 해석 — PokéAPI 의 `evolution_details` 중 이 앱이 재현할 수 있는 것만 옮긴다.
final class EvoRequirementParsingTests: XCTestCase {
    private func detail(trigger: String? = nil, item: String? = nil,
                        happiness: Int? = nil) -> EvolutionDetail {
        let json = """
        {"trigger":\(trigger.map { "{\"name\":\"\($0)\"}" } ?? "null"),
         "item":\(item.map { "{\"name\":\"\($0)\"}" } ?? "null"),
         "min_happiness":\(happiness.map(String.init) ?? "null")}
        """
        return try! JSONDecoder().decode(EvolutionDetail.self, from: Data(json.utf8))
    }

    /// 표에 없는 종으로 고정한다 — 카탈로그가 우연히 끼어들지 않게.
    private let uncatalogued = 4   // 파이리

    func testItemBecomesAnItemRequirement() {
        XCTAssertEqual(PokeAPIClient.requirement(from: [detail(trigger: "use-item", item: "fire-stone")],
                                                 speciesID: uncatalogued, parentLevel: 1),
                       .item(["fire-stone"]))
    }

    /// 통신교환은 도구가 없다 — 이 앱에는 교환 상대가 없으므로 연결의 끈으로 대신한다.
    func testTradeBecomesTheLinkingCord() {
        XCTAssertEqual(PokeAPIClient.requirement(from: [detail(trigger: "trade")],
                                                 speciesID: uncatalogued, parentLevel: 1),
                       .item([EvolutionItem.linkingCord.rawValue]))
    }

    func testHappinessBecomesFriendship() {
        XCTAssertEqual(PokeAPIClient.requirement(from: [detail(trigger: "level-up", happiness: 160)],
                                                 speciesID: uncatalogued, parentLevel: 1),
                       .friendship)
    }

    /// 재현할 수 없는 조건(장소·특정 기술)은 막다른 벽이 되면 안 된다 — 명시된 레벨이 없으면
    /// `EvoBalance` 규칙(앞 단계 레벨 + 여유분, 하한 20)으로 떨어져 여전히 진화할 길이 남는다.
    /// (카탈로그에도 없는 종이라 폴백 규칙까지 내려간다.)
    func testUnreproducibleConditionsFallBackToALevel() {
        XCTAssertEqual(PokeAPIClient.requirement(from: [detail(trigger: "level-up")],
                                                 speciesID: uncatalogued, parentLevel: 1),
                       .level(20))
        XCTAssertEqual(PokeAPIClient.requirement(from: [], speciesID: uncatalogued, parentLevel: 1), .none)
        XCTAssertEqual(PokeAPIClient.requirement(from: nil, speciesID: uncatalogued, parentLevel: 1), .none)
    }

    /// 모르는 아이템이면 그 조건은 없는 셈 치고 레벨 규칙으로 떨어진다 — 카탈로그에 없는 도구를
    /// 요구한다고 못 넘는 벽이 되면 안 된다.
    func testUnknownItemFallsBackToALevel() {
        XCTAssertEqual(PokeAPIClient.requirement(from: [detail(trigger: "use-item", item: "odd-rock")],
                                                 speciesID: uncatalogued, parentLevel: 1),
                       .level(20))
    }

    /// 여러 건이면 재현 가능한 첫 번째를 쓴다 — 본가도 그중 하나만 만족하면 된다.
    func testPicksTheFirstReproducibleCondition() {
        let details = [detail(trigger: "level-up"), detail(trigger: "use-item", item: "moon-stone")]
        XCTAssertEqual(PokeAPIClient.requirement(from: details, speciesID: uncatalogued, parentLevel: 1),
                       .item(["moon-stone"]))
    }
}

/// 체인 트리 조립 — **조건이 아예 없는 자식 간선은 진화가 아니다.**
///
/// PokéAPI DB 에는 피오네도 마나피도 진화 관계가 없는데(`evolves_from` 둘 다 null), REST 직렬화기가
/// "한 체인에 뿌리 없는 종이 둘"인 체인 250 을 임의로 피오네→마나피로 포개 내보낸다. 진짜 진화가
/// 아니라서 `evolution_details` 가 빈 배열인 것이 그 표식이다 — 전 데이터 전수 확인(2026-09-30):
/// 진짜 진화 간선 치고 details 가 빈 것은 0건, 이 부류는 체인 250 하나뿐이다.
final class FabricatedChainEdgeTests: XCTestCase {
    /// 실제 응답에서 잘라 온 픽스처(`evolution-chain/250`, 2026-09-30 캡처).
    private let phioneChain = """
    {"chain": {"is_baby": false,
      "species": {"name": "phione", "url": "https://pokeapi.co/api/v2/pokemon-species/489/"},
      "evolution_details": [],
      "evolves_to": [{"is_baby": false,
        "species": {"name": "manaphy", "url": "https://pokeapi.co/api/v2/pokemon-species/490/"},
        "evolution_details": [],
        "evolves_to": []}]}}
    """

    func testAnEdgeWithoutDetailsIsNotAnEvolution() throws {
        let dto = try JSONDecoder().decode(ChainDTO.self, from: Data(phioneChain.utf8))
        let tree = PokeAPIClient.node(from: dto.chain)
        XCTAssertEqual(tree.speciesID, 489)
        XCTAssertTrue(tree.children.isEmpty, "피오네가 마나피로 진화하게 됐다 — 지어낸 간선이 살아 있다")
    }

    /// 대조군 — 조건이 실린 진짜 간선은 그대로 이어진다(`evolution-chain/18` 식스테일 모양,
    /// 게이트가 늘 꺼져 있지 않은지 보증).
    func testARealEdgeWithDetailsStillParses() throws {
        let vulpixChain = """
        {"chain": {"is_baby": false,
          "species": {"name": "vulpix", "url": "https://pokeapi.co/api/v2/pokemon-species/37/"},
          "evolution_details": [],
          "evolves_to": [{"is_baby": false,
            "species": {"name": "ninetales", "url": "https://pokeapi.co/api/v2/pokemon-species/38/"},
            "evolution_details": [{"trigger": {"name": "use-item"}, "item": {"name": "fire-stone"},
                                   "min_happiness": null, "min_level": null}],
            "evolves_to": []}]}}
        """
        let dto = try JSONDecoder().decode(ChainDTO.self, from: Data(vulpixChain.utf8))
        let tree = PokeAPIClient.node(from: dto.chain)
        XCTAssertEqual(tree.children.map(\.speciesID), [38])
        XCTAssertEqual(tree.children.first?.requirementRaw, .item(["fire-stone"]))
    }
}

@MainActor
final class EvolutionGateTests: XCTestCase {
    private var clock = Date(timeIntervalSince1970: 1_000_000)

    private func makeStore() -> PlayerStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("evogate-\(UUID().uuidString).json")
        return PlayerStore(fileURL: url, rng: SeededRNG(seed: 11), now: { self.clock },
                           defaults: UserDefaults(suiteName: "evogate-\(UUID().uuidString)")!)
    }

    /// 조건이 실린 라인 — 1 이 2 가 되려면 `requirement` 가 필요하다.
    private func line(_ requirement: EvoRequirementRaw) -> EvoLine {
        EvoLine(baseID: 1,
                tree: EvoNode(speciesID: 1, children: [
                    EvoNode(speciesID: 2, children: [], requirementRaw: requirement),
                ]),
                rarity: .common, names: [:])
    }

    private func ready(_ store: PlayerStore) -> Individual {
        let individual = Individual(baseID: 1, speciesID: 1, pathIDs: [1], nature: .serious,
                                    exp: 999_000_000, obtainedAt: clock, grade: .common)
        store.addForTesting(individual)
        return individual
    }

    /// 도구가 없으면 못 간다 — 경험치가 넘쳐도.
    func testItemEvolutionIsBlockedWithoutTheItem() {
        let store = makeStore()
        let individual = ready(store)
        XCTAssertFalse(store.evolve(individualID: individual.id, to: 2, line: line(.item(["fire-stone"]))))
        XCTAssertEqual(store.state.box.first?.speciesID, 1)
    }

    /// 도구가 있으면 간다.
    func testItemEvolutionProceedsWithTheItem() {
        let store = makeStore()
        let individual = ready(store)
        store.grantForTesting(.fireStone)
        XCTAssertTrue(store.evolve(individualID: individual.id, to: 2, line: line(.item(["fire-stone"]))))
        XCTAssertEqual(store.state.box.first?.speciesID, 2)
    }

    /// 실패한 진화는 도구를 먹지 않는다 — 트리에 없는 종으로 시도한 경우.
    /// (도구 진화는 레벨을 안 보므로 "경험치가 모자란" 실패는 더 이상 없다 — Task 7.)
    func testAFailedEvolutionKeepsTheItem() {
        let store = makeStore()
        let individual = ready(store)
        store.grantForTesting(.fireStone)
        XCTAssertFalse(store.evolve(individualID: individual.id, to: 99,
                                    line: line(.item(["fire-stone"]))), "라인에 없는 종인데 된다")
        XCTAssertEqual(store.count(of: .fireStone), 1, "실패한 진화가 도구를 먹었다")
    }

    /// 친밀도는 **함께한 시간**으로 판단한다 — 리본 1단계와 같은 문턱이라 화면에서 이미 익숙하다.
    func testFriendshipNeedsTimeTogether() {
        let store = makeStore()
        let individual = ready(store)
        store.setPartner(individual.id)
        XCTAssertFalse(store.evolve(individualID: individual.id, to: 2, line: line(.friendship)))
        clock = clock.addingTimeInterval(Double(EvoRequirement.friendshipSeconds) + 60)
        XCTAssertTrue(store.evolve(individualID: individual.id, to: 2, line: line(.friendship)))
    }

    /// 도구는 진화에 써도 남고, **다른 개체에게 다시 쓸 수 있다.** 이게 구조의 핵심이다 —
    /// 없어지면 두 번째 개체를 위해 또 며칠을 기다려야 하고, 그건 사실상 막힌 것과 같다.
    func testItemsSurviveAndWorkOnTheNextIndividual() {
        for item in [EvolutionItem.metalCoat, .fireStone] {
            let store = makeStore()
            let first = ready(store), second = ready(store)
            store.grantForTesting(item)
            let need = line(.item([item.rawValue]))
            XCTAssertTrue(store.evolve(individualID: first.id, to: 2, line: need))
            XCTAssertEqual(store.count(of: item), 1, "\(item) 이 없어졌다")
            XCTAssertTrue(store.evolve(individualID: second.id, to: 2, line: need),
                          "\(item) 을 두 번째 개체에 못 쓴다")
        }
    }

    /// 조건이 없으면 예전처럼 경험치만으로 간다 — 대부분(346종)이 여기 해당한다.
    func testUnconditionalEvolutionStillWorks() {
        let store = makeStore()
        let individual = ready(store)
        XCTAssertTrue(store.evolve(individualID: individual.id, to: 2, line: line(.none)))
    }
}

/// 리본 파트너가 **자기에게 필요한** 도구를 물어 온다.
final class ForageTests: XCTestCase {
    /// 마그마그(126)는 마그마부스터 하나만 필요하다 — 갈래가 하나인 대표.
    private let magby: [EvolutionItem] = ForageCatalog.needs(speciesID: 126, region: nil)

    func testNothingBelowTheChance() {
        XCTAssertNil(PlayerStore.forage(ribbon: .bond, needs: magby, roll: 0.99, pick: 0))
    }

    /// 경계는 선언한 확률에서 파생해야 한다 — 숫자를 박아 두면 밸런스를 고칠 때마다
    /// 테스트가 깨지기만 하고 무엇을 지키는지는 알려주지 않는다.
    func testBoundaryMatchesTheDeclaredChance() {
        for ribbon in Ribbon.allCases {
            let inside = Double(ribbon.foragePermille - 1) / 1000
            let outside = Double(ribbon.foragePermille) / 1000
            XCTAssertNotNil(PlayerStore.forage(ribbon: ribbon, needs: magby, roll: inside, pick: 0),
                            "\(ribbon): 선언한 확률 안인데 안 나온다")
            XCTAssertNil(PlayerStore.forage(ribbon: ribbon, needs: magby, roll: outside, pick: 0),
                         "\(ribbon): 선언한 확률 밖인데 나온다")
        }
    }

    /// 단계가 오를수록 자주 물어 와야 한다 — 뒤집히면 오래 함께한 게 손해가 된다.
    func testHigherRibbonsForageMoreOften() {
        let sorted = Ribbon.allCases.sorted()
        for (lower, higher) in zip(sorted, sorted.dropFirst()) {
            XCTAssertLessThan(lower.foragePermille, higher.foragePermille)
        }
    }

    /// 자기가 쓸 것만 나온다. 이게 이 구조의 전부다 — 마그마그가 심해의비늘을 물어 오면
    /// 예전의 무작위 잡화로 돌아간 것이다.
    func testOnlyBringsWhatThisIndividualNeeds() {
        XCTAssertEqual(magby, [.magmarizer])
        for i in 0..<200 {
            let pick = Double(i) / 200
            let item = PlayerStore.forage(ribbon: .lifelong, needs: magby, roll: 0, pick: pick)
            XCTAssertEqual(item, .magmarizer, "pick=\(pick) 에서 엉뚱한 걸 물어 왔다")
        }
    }

    /// 도구가 필요 없는 종은 아무것도 못 물어 온다 — 확률이 아무리 높아도.
    func testSpeciesThatNeedNothingForageNothing() {
        let none = ForageCatalog.needs(speciesID: 1, region: nil)   // 이상해씨는 레벨업 진화
        XCTAssertTrue(none.isEmpty)
        XCTAssertNil(PlayerStore.forage(ribbon: .lifelong, needs: none, roll: 0, pick: 0))
    }

    /// 갈래가 여럿이면 그 중에서만 고른다 — 이브이는 돌이 다섯이다.
    func testMultipleBranchesStayWithinTheSet() {
        let eevee = Set(ForageCatalog.needs(speciesID: 133, region: nil))
        XCTAssertEqual(eevee, [.waterStone, .thunderStone, .fireStone, .leafStone, .iceStone])
        for i in 0..<200 {
            guard let item = PlayerStore.forage(ribbon: .lifelong, needs: Array(eevee),
                                                roll: 0, pick: Double(i) / 200) else {
                return XCTFail("이브이가 아무것도 못 물어 왔다")
            }
            XCTAssertTrue(eevee.contains(item), "\(item) 은 이브이의 갈래가 아니다")
        }
    }

    /// pick 이 1.0 이어도 배열 밖으로 나가지 않는다.
    func testPickAtTheTopDoesNotOverflow() {
        XCTAssertNotNil(PlayerStore.forage(ribbon: .lifelong, needs: magby, roll: 0, pick: 1.0))
    }

    /// **이미 가진 도구는 다시 안 물어 온다.** 도구는 없어지지 않으므로 두 번째는 쓸모가 없고,
    /// 그대로 두면 다 모은 개체의 채집 굴림이 영원히 헛돈다.
    func testAlreadyOwnedItemsAreNotBroughtAgain() {
        XCTAssertNil(PlayerStore.forage(ribbon: .lifelong, needs: magby, owned: [.magmarizer],
                                        roll: 0, pick: 0))
    }

    /// 갈래가 여럿이면 **아직 없는 것 중에서만** 고른다 — 이브이가 돌 넷을 가졌으면 남은 하나.
    func testOnlyMissingBranchesRemainCandidates() {
        let eevee = ForageCatalog.needs(speciesID: 133, region: nil)
        let owned: Set<EvolutionItem> = [.waterStone, .thunderStone, .fireStone, .leafStone]
        for i in 0..<50 {
            XCTAssertEqual(PlayerStore.forage(ribbon: .lifelong, needs: eevee, owned: owned,
                                              roll: 0, pick: Double(i) / 50),
                           .iceStone, "안 가진 하나만 나와야 한다")
        }
    }
}

/// 같은 종이라도 지방에 따라 필요한 도구가 갈리는 10건. `RegionBalance.branchesByRegion` 이
/// *도착 종*이 갈리는 경우를 다루는 것과 짝이다 — 여기는 도착 종이 같고 도구만 갈린다.
final class ForageRegionScopeTests: XCTestCase {
    /// 알로라 식스테일은 얼음의돌, 관동 식스테일은 불꽃의돌. 서로의 것을 물어 오면 안 된다.
    func testVulpixNeedsDifferentStonesByRegion() {
        XCTAssertEqual(ForageCatalog.needs(speciesID: 37, region: nil), [.fireStone])
        XCTAssertEqual(ForageCatalog.needs(speciesID: 37, region: .alola), [.iceStone])
    }

    /// 원종은 도구 없이 레벨업으로 진화하는 쪽 — 관동 모래두지·찌리리공·달막화는 빈손이어야 한다.
    func testOriginalFormsThatEvolveByLevelForageNothing() {
        for (species, region) in [(27, Region.alola), (100, .hisui), (554, .galar)] {
            XCTAssertTrue(ForageCatalog.needs(speciesID: species, region: nil).isEmpty,
                          "#\(species) 원종은 도구가 필요 없는데 물어 온다")
            XCTAssertFalse(ForageCatalog.needs(speciesID: species, region: region).isEmpty,
                           "#\(species) \(region) 는 도구가 필요한데 못 물어 온다")
        }
    }

    /// 가라두구 계열은 가라르 야돈만, 왕의징표석은 관동 야돈만.
    func testSlowpokeBranchesAreRegionExclusive() {
        XCTAssertEqual(ForageCatalog.needs(speciesID: 79, region: nil), [.kingsRock])
        XCTAssertEqual(Set(ForageCatalog.needs(speciesID: 79, region: .galar)),
                       [.galaricaCuff, .galaricaWreath])
    }

    /// 양쪽이 같은 도구를 쓰는 종은 좁히지 않는다 — 히스이 가디도 불꽃의돌로 진화한다.
    func testSharedItemBranchesAreNotNarrowed() {
        XCTAssertEqual(ForageCatalog.needs(speciesID: 58, region: nil), [.fireStone])
        XCTAssertEqual(ForageCatalog.needs(speciesID: 58, region: .hisui), [.fireStone])
    }
}

/// 표 자체가 성립하는가. 채집(`ForageCatalog`)과 진화 게이트(`PokeAPIClient.requirement`)는
/// 같은 PokéAPI 필드에서 나오지만 **인코딩이 둘이다** — 한쪽만 고치면 "쓸 수도 없는 걸 물어
/// 오거나", 반대로 "필요한데 영영 못 얻는" 상태가 된다. 여기서 그 둘을 맞대 본다.
final class ForageCatalogIntegrityTests: XCTestCase {
    /// 표의 모든 갈래는 진화 게이트가 같은 도구를 요구해야 한다. 통신교환은 지닌 물건이
    /// 조건이므로(`trade` + `held_item`) 게이트가 보는 모양 그대로 넣어 확인한다.
    func testEveryEntryMatchesTheEvolutionGate() {
        for (from, needs) in ForageCatalog.bySpecies {
            for need in needs {
                let byItem: EvoRequirementRaw = PokeAPIClient.requirement(from: [
                    EvolutionDetail(trigger: NamedRef(name: "use-item", url: nil),
                                    item: NamedRef(name: need.item.rawValue, url: nil),
                                    held_item: nil, min_happiness: nil, min_level: nil,
                                    gender: nil, base_form: nil, required_pokemon_form: nil),
                ], speciesID: from, parentLevel: 1)
                XCTAssertEqual(byItem, .item([need.item.rawValue]),
                               "#\(from) → #\(need.to): 게이트가 \(need.item) 을 못 알아본다")
            }
        }
    }

    /// 갈래가 비어 있는 종을 표에 남기면 "필요한 게 있다"고 잘못 읽힌다.
    func testNoEmptyEntries() {
        for (from, needs) in ForageCatalog.bySpecies {
            XCTAssertFalse(needs.isEmpty, "#\(from) 이 빈 갈래로 남아 있다")
        }
    }

    /// 같은 (도착 종, 도구) 가 두 번 들어가면 그 갈래만 뽑힐 확률이 두 배가 된다 —
    /// PokéAPI 는 지방 변형을 별개 행으로 돌려주므로 생성기에서 걸러야 한다.
    func testNoDuplicateBranches() {
        for (from, needs) in ForageCatalog.bySpecies {
            let keys = needs.map { "\($0.to)-\($0.item.rawValue)" }
            XCTAssertEqual(Set(keys).count, keys.count, "#\(from) 에 같은 갈래가 두 번 있다")
        }
    }

    /// 지방을 좁힌 갈래는 실제로 그 지방 모습이 있는 종이어야 한다.
    func testNarrowedBranchesPointAtRealRegionalForms() {
        for (from, needs) in ForageCatalog.bySpecies {
            for need in needs {
                guard case .only(let region) = need.scope, let region else { continue }
                XCTAssertTrue(RegionalFormCatalog.forms(speciesID: from).contains { $0.region == region },
                              "#\(from) 에 \(region) 모습이 없는데 그 지방 전용 갈래가 있다")
            }
        }
    }
}

/// 상점에 없는 도구는 **얻는 길이 파트너뿐**이라 화면이 그 말을 해야 한다. 안 하면
/// "마그마부스터 필요"에서 끝나 어디서 구하는지 알 수 없고, 진화가 고장난 것처럼 보인다.
///
/// 그 일은 두 곳이 나눠 맡는다: **이름은 갈래 줄**(`shortNeed`), **얻는 방법은 섹션 안내**
/// (`evolutionLockedHint`) 한 줄. 갈래마다 문장을 붙이면 이브이(8갈래)에서 화면을 먹는다.
final class ForagedItemHintTests: XCTestCase {
    func testEachBranchNamesTheItemItWaitsFor() {
        for lang in AppLanguage.allCases {
            // 돌이든 특수 도구든 얻는 길은 하나뿐이므로 표기도 같아야 한다.
            let line = EvoLine(baseID: 1, tree: EvoNode(speciesID: 1, children: []),
                               rarity: .common, names: [:])
            for item in [EvolutionItem.magmarizer, .fireStone, .linkingCord] {
                XCTAssertEqual(IndividualDetailView.shortNeed(.item([item]), line: line, l: L(lang)),
                               item.label(lang), "\(lang) \(item): 갈래 줄에 이름이 없다")
            }
        }
    }

    /// 안내가 실제로 파트너를 가리키는지 — 한국어에서만 문자열로 확인한다(번역은 빈 문구만).
    func testTheHintPointsAtThePartner() {
        XCTAssertTrue(L(.ko).evolutionLockedHint.contains("파트너"),
                      "도구 안내가 얻는 방법을 안 알려준다: \(L(.ko).evolutionLockedHint)")
        for lang in AppLanguage.allCases {
            XCTAssertFalse(L(lang).evolutionLockedHint.isEmpty, "\(lang): 안내가 비었다")
        }
    }
}

/// [회귀] `EvoLine.init` 은 항상 `keepingSupportedSpecies()` 로 트리를 다시 만든다. 그 재구성이
/// 요구 조건을 안 옮기면 돌·연결의 끈이 필요한 진화가 **조건 없이 열린다** — 실제로 그랬다.
final class EvoTreePruningKeepsRequirementsTests: XCTestCase {
    func testPruningCarriesTheRequirement() {
        let tree = EvoNode(speciesID: 1, children: [
            EvoNode(speciesID: 2, children: [], requirementRaw: .item(["fire-stone"])),
        ])
        let pruned = tree.keepingSupportedSpecies()
        XCTAssertEqual(pruned?.node(withID: 2)?.requirementRaw, .item(["fire-stone"]),
                       "가지치기가 요구 조건을 버렸다 — 조건이 필요한 진화가 그냥 열린다")
    }

    /// 라인을 만드는 실제 경로로도 확인한다 — `keepingSupportedSpecies` 만 보면 배선이 빠져도 통과한다.
    func testTheLineKeepsRequirementsToo() {
        let line = EvoLine(baseID: 1,
                           tree: EvoNode(speciesID: 1, children: [
                               EvoNode(speciesID: 2, children: [], requirementRaw: .friendship),
                           ]),
                           rarity: .common, names: [:])
        XCTAssertEqual(line.tree.node(withID: 2)?.requirementRaw, .friendship)
    }
}

/// 상점 진열 — 품목이 자기 분류를 알아야 한다. 뷰가 목록을 손으로 나열하면 새 품목이
/// 어느 칸에도 안 들어가 **팔리지 않는 채로** 조용히 남는다(사탕이 그런 식으로 한 번 새어 나갔다).
final class ShopCategoryTests: XCTestCase {
    /// 모든 품목이 정확히 한 칸에 속한다 — 빠진 품목이 있으면 상점에서 사라진다.
    func testEveryItemLandsInExactlyOneSection() {
        let placed = ShopCategory.allCases.flatMap { c in ShopItem.allCases.filter { $0.category == c } }
        XCTAssertEqual(Set(placed), Set(ShopItem.allCases), "어느 칸에도 없는 품목이 있다")
        XCTAssertEqual(placed.count, ShopItem.allCases.count, "두 칸에 걸친 품목이 있다")
    }

    /// 분류 기준은 **쓰면 없어지는가** 하나다 — 상점과 가방이 같은 칸 이름을 쓰게 하려고
    /// 종류별(사탕·폼)로 나누던 것을 합쳤다. 같은 물건이 화면마다 다른 칸에 있으면 안 된다.
    func testCategoriesFollowWhetherTheItemIsSpent() {
        for item in ShopItem.allCases {
            XCTAssertEqual(item.category, item.isCharm ? .charm : .consumable, "\(item)")
        }
        XCTAssertEqual(ShopItem.expCandy.category, ShopItem.megaStone.category,
                       "사탕과 메가스톤은 둘 다 쓰면 없어진다 — 같은 칸이어야 한다")
    }

    /// 상점과 가방이 **같은 이름**을 써야 한다. 각자 문구를 들고 있으면 다시 갈라진다.
    @MainActor
    func testShopAndBagShareCategoryNames() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cat-\(UUID().uuidString).json")
        let store = PlayerStore(fileURL: url, rng: SeededRNG(seed: 1),
                                now: { Date(timeIntervalSince1970: 0) })
        store.seedForTesting(wallet: 100_000_000_000, slots: 3, eggs: 0,
                             at: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(store.buy(ShopItem.expCandy))
        XCTAssertTrue(store.buy(ShopItem.shinyCharm))
        let titles = Set(BagTabView.sections(store).filter { !$0.rows.isEmpty }.map(\.title))
        XCTAssertTrue(titles.contains(ShopCategory.consumable.title(.ko)), titles.description)
        XCTAssertTrue(titles.contains(ShopCategory.charm.title(.ko)), titles.description)
    }

    /// 진화 도구는 `ShopItem` 이 아니라 별도 카탈로그다 — 두 목록이 겹치면 같은 것이 두 번 팔린다.
    func testEvolutionItemsAreNotShopItems() {
        let shopKeys = Set(ShopItem.allCases.map(\.rawValue))
        for item in EvolutionItem.allCases {
            XCTAssertFalse(shopKeys.contains(item.rawValue), "\(item) 이 두 목록에 다 있다")
        }
    }

    func testEverySectionHasATitleInEveryLanguage() {
        for category in ShopCategory.allCases {
            for lang in [AppLanguage.ko, .en, .ja] {
                XCTAssertFalse(category.title(lang).isEmpty)
            }
        }
    }
}

/// 통신교환 — 25종 중 15종은 특정 물건을 들고 교환해야 한다. 연결의 끈 하나로 뭉뚱그리면
/// 금속코트·에레키부스터 같은 것이 게임에서 아예 사라진다(사용자 지적).
final class TradeHeldItemTests: XCTestCase {
    private func tradeDetail(held: String?) -> EvolutionDetail {
        let json = """
        {"trigger":{"name":"trade"},"item":null,
         "held_item":\(held.map { "{\"name\":\"\($0)\"}" } ?? "null"),"min_happiness":null}
        """
        return try! JSONDecoder().decode(EvolutionDetail.self, from: Data(json.utf8))
    }

    func testHeldItemWinsOverTheCord() {
        XCTAssertEqual(PokeAPIClient.requirement(from: [tradeDetail(held: "metal-coat")],
                                                 speciesID: 4, parentLevel: 1),
                       .item(["metal-coat"]))
        XCTAssertEqual(PokeAPIClient.requirement(from: [tradeDetail(held: "electirizer")],
                                                 speciesID: 4, parentLevel: 1),
                       .item(["electirizer"]))
    }

    /// 물건 없이 교환하는 10종만 연결의 끈이 담당한다.
    func testPlainTradeStillUsesTheCord() {
        XCTAssertEqual(PokeAPIClient.requirement(from: [tradeDetail(held: nil)],
                                                 speciesID: 4, parentLevel: 1),
                       .item([EvolutionItem.linkingCord.rawValue]))
    }

    /// 모르는 물건이면 연결의 끈으로 떨어진다 — 못 넘는 벽을 만들지 않는다.
    func testUnknownHeldItemFallsBackToTheCord() {
        XCTAssertEqual(PokeAPIClient.requirement(from: [tradeDetail(held: "odd-charm")],
                                                 speciesID: 4, parentLevel: 1),
                       .item([EvolutionItem.linkingCord.rawValue]))
    }

    /// 실제로 쓰이는 13종류가 전부 카탈로그에 있어야 한다 — 하나라도 빠지면 그 진화가
    /// 조건 없이 열리거나(모르는 이름) 연결의 끈으로 뭉뚱그려진다.
    func testEveryTradeHeldItemIsCatalogued() {
        let used = ["metal-coat", "electirizer", "magmarizer", "kings-rock", "dragon-scale",
                    "dubious-disc", "protector", "reaper-cloth", "deep-sea-tooth",
                    "deep-sea-scale", "sachet", "whipped-dream", "up-grade"]
        let obtainable = Set(ForageCatalog.bySpecies.values.flatMap { $0 }.map(\.item))
        for name in used {
            guard let item = EvolutionItem.named(name) else {
                return XCTFail("\(name) 이 카탈로그에 없다")
            }
            XCTAssertTrue(obtainable.contains(item), "\(name) 을 물어 오는 종이 없다")
        }
    }
}

/// [회귀] 조건이 **태생 모습마다 다른** 갈래. 데인차는 위작이면 깨진포트, 진작이면 이빠진포트로
/// 포트데스가 된다. 파서가 두 줄을 하나로 접으면 진작 데인차가 깨진포트를 요구한다(실측).
final class FormSplitRequirementTests: XCTestCase {
    /// `evolution-chain/449` 에서 잘라 왔다 — 두 줄 모두 `required_pokemon_form` 을 들고 있다.
    private let sinisteaChain = """
    {"chain": {
      "species": {"name": "sinistea", "url": "https://pokeapi.co/api/v2/pokemon-species/854/"},
      "evolution_details": [],
      "evolves_to": [{
        "species": {"name": "polteageist", "url": "https://pokeapi.co/api/v2/pokemon-species/855/"},
        "evolution_details": [
          {"trigger": {"name": "use-item"}, "item": {"name": "cracked-pot"},
           "required_pokemon_form": {"name": "sinistea-phony"}},
          {"trigger": {"name": "use-item"}, "item": {"name": "chipped-pot"},
           "required_pokemon_form": {"name": "sinistea-antique"}}],
        "evolves_to": []}]}}
    """

    func testTheDefaultFormKeepsTheBaseRequirement() throws {
        let dto = try JSONDecoder().decode(ChainDTO.self, from: Data(sinisteaChain.utf8))
        let node = try XCTUnwrap(PokeAPIClient.node(from: dto.chain).node(withID: 855))
        XCTAssertEqual(node.requirementRaw, .item(["cracked-pot"]),
                       "위작(기본)이 깨진포트를 요구하지 않는다")
    }

    func testTheRareVariantGetsItsOwnRequirement() throws {
        let dto = try JSONDecoder().decode(ChainDTO.self, from: Data(sinisteaChain.utf8))
        let node = try XCTUnwrap(PokeAPIClient.node(from: dto.chain).node(withID: 855))
        XCTAssertEqual(node.formRequirementsRaw["antique"], .item(["chipped-pot"]),
                       "진작이 이빠진포트를 요구하지 않는다: \(node.formRequirementsRaw)")
    }

    /// 대조군 — 태생 모습과 무관한 `required_pokemon_form`(이브이 19줄 부류)은 **기본 조건으로
    /// 흡수**돼야 한다. 값의 유무로 가르면 이브이가 조건을 통째로 잃는다.
    func testAnUnknownFormNameFallsIntoTheBaseRequirement() throws {
        let eeveeChain = """
        {"chain": {
          "species": {"name": "eevee", "url": "https://pokeapi.co/api/v2/pokemon-species/133/"},
          "evolution_details": [],
          "evolves_to": [{
            "species": {"name": "vaporeon", "url": "https://pokeapi.co/api/v2/pokemon-species/134/"},
            "evolution_details": [
              {"trigger": {"name": "use-item"}, "item": {"name": "water-stone"},
               "required_pokemon_form": {"name": "eevee-starter"}}],
            "evolves_to": []}]}}
        """
        let dto = try JSONDecoder().decode(ChainDTO.self, from: Data(eeveeChain.utf8))
        let node = try XCTUnwrap(PokeAPIClient.node(from: dto.chain).node(withID: 134))
        XCTAssertEqual(node.requirementRaw, .item(["water-stone"]))
        XCTAssertTrue(node.formRequirementsRaw.isEmpty, "\(node.formRequirementsRaw)")
    }

    /// 종 이름에 하이픈이 있어도 변종 키를 바르게 뽑는다 — 첫 하이픈으로 자르면 깨진다.
    func testVariantKeysSurviveHyphenatedSpeciesNames() {
        let detail = PokeAPIClient.detailForTesting(requiredForm: "sinistea-antique")
        XCTAssertEqual(PokeAPIClient.formVariantKey(detail, parentSpeciesID: 854), "antique")
        let unrelated = PokeAPIClient.detailForTesting(requiredForm: "eevee-starter")
        XCTAssertNil(PokeAPIClient.formVariantKey(unrelated, parentSpeciesID: 133))
    }

    /// 줄 순서에 기대면 안 된다 — 진작 줄이 **먼저** 와도 기본 조건은 위작의 것이어야 한다.
    /// (`own` 필터가 모습 전용 줄을 안 빼면 먼저 온 이빠진포트가 이긴다. 위 두 테스트는 위작 줄이
    /// 먼저 오는 응답이라 필터를 지워도 통과한다 — 순서를 뒤집은 이 테스트만 그 필터를 지킨다.)
    func testTheBaseRequirementDoesNotDependOnLineOrder() throws {
        let reversed = """
        {"chain": {
          "species": {"name": "sinistea", "url": "https://pokeapi.co/api/v2/pokemon-species/854/"},
          "evolution_details": [],
          "evolves_to": [{
            "species": {"name": "polteageist", "url": "https://pokeapi.co/api/v2/pokemon-species/855/"},
            "evolution_details": [
              {"trigger": {"name": "use-item"}, "item": {"name": "chipped-pot"},
               "required_pokemon_form": {"name": "sinistea-antique"}},
              {"trigger": {"name": "use-item"}, "item": {"name": "cracked-pot"},
               "required_pokemon_form": {"name": "sinistea-phony"}}],
            "evolves_to": []}]}}
        """
        let dto = try JSONDecoder().decode(ChainDTO.self, from: Data(reversed.utf8))
        let node = try XCTUnwrap(PokeAPIClient.node(from: dto.chain).node(withID: 855))
        XCTAssertEqual(node.requirementRaw, .item(["cracked-pot"]), "먼저 온 줄이 기본 조건을 가로챘다")
        XCTAssertEqual(node.formRequirementsRaw["antique"], .item(["chipped-pot"]))
    }

    /// `EvoLine.init` 은 항상 `keepingSupportedSpecies()` 를 지난다 — 트리를 다시 만들면서 모습별
    /// 조건을 빠뜨리면 파서가 맞아도 진작이 다시 위작의 조건을 쓴다.
    func testPruningTheTreeKeepsTheFormRequirements() throws {
        let dto = try JSONDecoder().decode(ChainDTO.self, from: Data(sinisteaChain.utf8))
        let tree = try XCTUnwrap(PokeAPIClient.node(from: dto.chain).keepingSupportedSpecies())
        let node = try XCTUnwrap(tree.node(withID: 855))
        XCTAssertEqual(node.formRequirementsRaw["antique"], .item(["chipped-pot"]))
    }

    private func sinisteaLine() -> EvoLine {
        let dto = try! JSONDecoder().decode(ChainDTO.self, from: Data(sinisteaChain.utf8))
        return EvoLine(baseID: 854, tree: PokeAPIClient.node(from: dto.chain),
                       rarity: .common, names: [:])
    }

    @MainActor private func store() -> PlayerStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sinistea-\(UUID().uuidString).json")
        return PlayerStore(fileURL: url, rng: SeededRNG(seed: 1),
                           now: { Date(timeIntervalSince1970: 1_000_000) })
    }

    @MainActor func testTheAntiqueOneAsksForTheChippedPot() {
        let s = store()
        XCTAssertEqual(s.requirement(for: 855, line: sinisteaLine(), region: nil,
                                     fixedForm: "antique"),
                       .item([.chippedPot]))
    }

    /// 대조군 — 위작(기본형)과 **옛 세이브의 nil** 은 깨진포트다. nil 을 진작으로 읽으면
    /// 변종이 없던 시절의 개체가 엉뚱한 도구를 기다린다.
    @MainActor func testThePhonyOneAndOldSavesAskForTheCrackedPot() {
        let s = store()
        for variant in [nil, "phony"] as [String?] {
            XCTAssertEqual(s.requirement(for: 855, line: sinisteaLine(), region: nil,
                                         fixedForm: variant),
                           .item([.crackedPot]), "variant=\(String(describing: variant))")
        }
    }
}

/// 물어 오는 도구도 태생 모습을 따라야 한다. 안 그러면 위작 데인차가 평생 못 쓸 이빠진포트를
/// 며칠 걸려 모은다 — 채집은 느리고(리본 기준 수십 B 토큰) 그 시간이 통째로 버려진다.
final class FormScopedForageTests: XCTestCase {
    func testThePhonyOneOnlyForagesTheCrackedPot() {
        XCTAssertEqual(ForageCatalog.needs(speciesID: 854, region: nil, fixedForm: nil),
                       [.crackedPot])
    }

    func testTheAntiqueOneOnlyForagesTheChippedPot() {
        XCTAssertEqual(ForageCatalog.needs(speciesID: 854, region: nil, fixedForm: "antique"),
                       [.chippedPot])
    }

    func testPoltchageistSplitsTheSameWay() {
        XCTAssertEqual(ForageCatalog.needs(speciesID: 1012, region: nil, fixedForm: nil),
                       [.unremarkableTeacup])
        XCTAssertEqual(ForageCatalog.needs(speciesID: 1012, region: nil, fixedForm: "artisan"),
                       [.masterpieceTeacup])
    }

    /// 대조군 — 모습으로 안 갈리는 종은 전부 그대로 물어 온다(치고마의 족자 둘은 **선택지**라
    /// 둘 다 유효하다). 게이트가 늘 켜져 있으면 안 된다.
    func testSpeciesWithoutAFormSplitAreUnchanged() {
        XCTAssertEqual(ForageCatalog.needs(speciesID: 891, region: nil, fixedForm: nil).count, 2)
        XCTAssertEqual(ForageCatalog.needs(speciesID: 25, region: nil, fixedForm: nil),
                       [.thunderStone])
    }
}

/// 태생 모습이 **실제 채집 굴림까지** 닿는가. 표만 맞아도 굴림 쪽이 모습을 빼먹으면 위작·골동이
/// 서로의 포트를 모은다 — 표 테스트(`FormScopedForageTests`)는 그걸 못 잡는다.
@MainActor
final class FormScopedForageProductionTests: XCTestCase {
    private var clock = Date(timeIntervalSince1970: 1_000_000)

    /// 반려 리본(700‰)으로 사탕을 `candies` 개 만들어 굴림을 그만큼 돌린다.
    private func forage(birthForm: String?, candies: Int = 40) -> PlayerStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("formforage-\(UUID().uuidString).json")
        let store = PlayerStore(fileURL: url, rng: SeededRNG(seed: 9), now: { self.clock },
                                defaults: UserDefaults(suiteName: "formforage-\(UUID().uuidString)")!)
        var individual = Individual(baseID: 854, speciesID: 854, pathIDs: [854], nature: .serious,
                                    obtainedAt: clock, grade: .common)
        individual.fixedForm = birthForm
        store.addForTesting(individual)
        store.setPartner(individual.id)
        store.update(todayTokens: 0, todayDate: "2026-01-01", hasUsageData: true)   // 기준선
        clock = clock.addingTimeInterval(90 * 86_400)
        let per = Ribbon.lifelong.tokensPerCandy
        for k in 1...candies {
            store.update(todayTokens: per * k, todayDate: "2026-01-01", hasUsageData: true)
        }
        return store
    }

    /// 골동 데인차는 이빠진포트만 — 깨진포트를 굴리면 안 된다. 이빠진포트가 한 번이라도
    /// 나와야 굴림이 실제로 돌았다는 뜻이라 빈 검사가 아니다.
    func testTheAntiqueOneNeverFetchesTheCrackedPot() {
        let store = forage(birthForm: "antique")
        XCTAssertEqual(store.state.inventory[EvolutionItem.crackedPot.rawValue] ?? 0, 0,
                       "골동 데인차가 쓸 수 없는 깨진포트를 물어 왔다")
        XCTAssertGreaterThan(store.state.inventory[EvolutionItem.chippedPot.rawValue] ?? 0, 0)
    }

    /// 대조군 — 위작(기본형)은 반대로 깨진포트만 받는다.
    func testThePhonyOneNeverFetchesTheChippedPot() {
        let store = forage(birthForm: nil)
        XCTAssertEqual(store.state.inventory[EvolutionItem.chippedPot.rawValue] ?? 0, 0,
                       "위작 데인차가 쓸 수 없는 이빠진포트를 물어 왔다")
        XCTAssertGreaterThan(store.state.inventory[EvolutionItem.crackedPot.rawValue] ?? 0, 0)
    }
}

/// 원작에서 **도구 두 개가 모두 유효한** 갈래가 있다 — 치고마의 족자 둘은 각각 다른 우라오스가
/// 된다. 조건을 도구 하나로 들면 뒤의 하나가 영영 쓸 데가 없다(실측: 물의족자가 그랬다).
final class ItemSetRequirementTests: XCTestCase {
    /// `evolution-chain/470` 에서 잘라 왔다. 실응답에는 도구 없는 `tower-of-darkness`·
    /// `tower-of-waters` 줄(옛 세대 트리거)이 앞에 둘 더 있어 그것도 그대로 둔다 — 파서가
    /// 도구 없는 줄을 건너뛰고 뒤의 둘을 모으는지 보려는 것이다.
    private let kubfuChain = """
    {"chain": {
      "species": {"name": "kubfu", "url": "https://pokeapi.co/api/v2/pokemon-species/891/"},
      "evolution_details": [],
      "evolves_to": [{
        "species": {"name": "urshifu", "url": "https://pokeapi.co/api/v2/pokemon-species/892/"},
        "evolution_details": [
          {"trigger": {"name": "tower-of-darkness"}},
          {"trigger": {"name": "tower-of-waters"}},
          {"trigger": {"name": "use-item"}, "item": {"name": "scroll-of-darkness"}},
          {"trigger": {"name": "use-item"}, "item": {"name": "scroll-of-waters"}}],
        "evolves_to": []}]}}
    """

    func testBothScrollsLandInTheRequirement() throws {
        let dto = try JSONDecoder().decode(ChainDTO.self, from: Data(kubfuChain.utf8))
        let node = try XCTUnwrap(PokeAPIClient.node(from: dto.chain).node(withID: 892))
        XCTAssertEqual(node.requirementRaw, .item(["scroll-of-darkness", "scroll-of-waters"]))
        XCTAssertEqual(node.requirement, .item([.scrollOfDarkness, .scrollOfWaters]))
    }

    /// 대조군 — 도구가 하나인 종은 원소 하나짜리 집합이다(집합화가 단일 경로를 안 바꿨는지).
    func testASingleItemIsStillASetOfOne() {
        XCTAssertEqual(PokeAPIClient.requirement(
            from: [PokeAPIClient.detailForTesting(item: "fire-stone")],
            parentSpeciesID: 0, speciesID: 4, parentLevel: 1), .item(["fire-stone"]))
    }

    /// 같은 도구가 줄마다 되풀이돼도 집합에는 한 번만 든다.
    func testARepeatedItemIsListedOnce() {
        XCTAssertEqual(PokeAPIClient.requirement(
            from: [PokeAPIClient.detailForTesting(item: "fire-stone"),
                   PokeAPIClient.detailForTesting(item: "fire-stone")],
            parentSpeciesID: 0, speciesID: 4, parentLevel: 1), .item(["fire-stone"]))
    }

    /// **아는 도구가 하나도 없으면 집합을 만들지 않는다.** `.item([])` 은 `.none` 으로 풀려
    /// 조건 없이 진화시킨다 — 마빌크가 레벨 폴백으로 떨어져야 하는 이유와 같은 자리다.
    func testUnknownItemsDoNotMakeAnEmptySet() {
        let need = PokeAPIClient.requirement(
            from: [PokeAPIClient.detailForTesting(item: "rare-candy")],
            parentSpeciesID: 0, speciesID: 4, parentLevel: 1)
        XCTAssertNotEqual(need, .item([]))
        XCTAssertEqual(need, .level(20), "조건 없음으로 떨어졌다 — 공짜 진화가 된다")
    }

    /// 해석 쪽 방어 — 원시 값이 빈 집합이나 전부 모르는 이름으로 와도 `.item([])` 이 되지 않는다.
    func testResolveNeverYieldsAnEmptyItemSet() {
        XCTAssertEqual(EvoNode(speciesID: 2, children: [], requirementRaw: .item([])).requirement, .none)
        XCTAssertEqual(EvoNode(speciesID: 2, children: [], requirementRaw: .item(["rare-candy"])).requirement,
                       .none)
        XCTAssertEqual(EvoNode(speciesID: 2, children: [],
                               requirementRaw: .item(["rare-candy", "fire-stone"])).requirement,
                       .item([.fireStone]), "아는 이름만 남아야 한다")
    }

    /// 지방 줄끼리도 도구를 모은다 — 첫 일치에서 끊으면 둘째 도구가 죽는다. (실응답에 이런 갈래는
    /// 아직 없어 줄을 직접 만든 합성 픽스처다. 모으는 동작 자체를 잠그는 용도.)
    func testRegionalItemsAreCollectedToo() {
        XCTAssertEqual(PokeAPIClient.regionalRequirement(from: [
            PokeAPIClient.detailForTesting(item: "ice-stone", requiredForm: "sandshrew-alola"),
            PokeAPIClient.detailForTesting(item: "water-stone", requiredForm: "sandshrew-alola"),
        ]), .item(["ice-stone", "water-stone"]))
    }

    /// 태생 모습 전용 줄 한 개가 도구를 들어도 그대로 집합으로 나온다.
    func testAFormRequirementCarriesItsItem() {
        let out = PokeAPIClient.formRequirements(
            from: [PokeAPIClient.detailForTesting(item: "chipped-pot", requiredForm: "sinistea-antique")],
            parentSpeciesID: 854, speciesID: 855, parentLevel: 1)
        XCTAssertEqual(out["antique"], .item(["chipped-pot"]))
    }

    @MainActor func testOwningEitherItemSatisfiesTheRequirement() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("kubfu-\(UUID().uuidString).json")
        let store = PlayerStore(fileURL: url, rng: SeededRNG(seed: 1),
                                now: { Date(timeIntervalSince1970: 1_000_000) })
        var kubfu = Individual(baseID: 891, speciesID: 891, pathIDs: [891], nature: .serious,
                               obtainedAt: Date(timeIntervalSince1970: 0), grade: .common)
        kubfu.growthRate = .mediumFast
        store.addForTesting(kubfu)
        let need = EvoRequirement.item([.scrollOfDarkness, .scrollOfWaters])
        XCTAssertFalse(store.meetsRequirement(need, for: store.state.box[0]))
        store.grantForTesting(EvolutionItem.scrollOfWaters)
        XCTAssertTrue(store.meetsRequirement(need, for: store.state.box[0]),
                      "둘 중 하나만 있어도 돼야 한다")
    }

    /// 접힌 줄 — 둘까지는 이름을 다 보이고, 셋부터는 첫 이름과 개수로 접는다(마빌크는 일곱).
    func testShortNeedNamesTwoAndFoldsThreeOrMore() {
        let line = EvoLine(baseID: 891, tree: EvoNode(speciesID: 891, children: []),
                           rarity: .common, names: [:])
        for lang in AppLanguage.allCases {
            let l = L(lang)
            XCTAssertEqual(
                IndividualDetailView.shortNeed(.item([.scrollOfDarkness, .scrollOfWaters]), line: line, l: l),
                "\(EvolutionItem.scrollOfDarkness.label(lang)) / \(EvolutionItem.scrollOfWaters.label(lang))")
            XCTAssertEqual(
                IndividualDetailView.shortNeed(.item([.fireStone]), line: line, l: l),
                EvolutionItem.fireStone.label(lang))
            XCTAssertEqual(
                IndividualDetailView.shortNeed(.item([.fireStone, .waterStone, .thunderStone]), line: line, l: l),
                l.evolveNeedsOneOf(EvolutionItem.fireStone.label(lang), 3))
        }
        XCTAssertEqual(L(.ko).evolveNeedsOneOf("불꽃의돌", 7), "불꽃의돌 등 7종")
        XCTAssertEqual(L(.en).evolveNeedsOneOf("Fire Stone", 7), "Fire Stone or 6 more")
    }
}

/// 진화할 때 쓴 도구가 결과의 모습을 정하고, 그 모습은 **평생 간다**(원작에서 되돌릴 방법이 없다).
final class EvolvedFormTests: XCTestCase {
    /// `evolution-chain/470` 에서 잘라 왔다(`ItemSetRequirementTests` 와 같은 모양 — 파일이 달라
    /// 다시 적는다). 실응답대로 도구 없는 `tower-*` 줄 둘이 앞에 있다.
    private let kubfuChain = """
    {"chain": {
      "species": {"name": "kubfu", "url": "https://pokeapi.co/api/v2/pokemon-species/891/"},
      "evolution_details": [],
      "evolves_to": [{
        "species": {"name": "urshifu", "url": "https://pokeapi.co/api/v2/pokemon-species/892/"},
        "evolution_details": [
          {"trigger": {"name": "tower-of-darkness"}},
          {"trigger": {"name": "tower-of-waters"}},
          {"trigger": {"name": "use-item"}, "item": {"name": "scroll-of-darkness"}},
          {"trigger": {"name": "use-item"}, "item": {"name": "scroll-of-waters"}}],
        "evolves_to": []}]}}
    """

    @MainActor private func kubfuStore() -> (PlayerStore, EvoLine) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("kubfu-\(UUID().uuidString).json")
        let store = PlayerStore(fileURL: url, rng: SeededRNG(seed: 1),
                                now: { Date(timeIntervalSince1970: 1_000_000) })
        var kubfu = Individual(baseID: 891, speciesID: 891, pathIDs: [891], nature: .serious,
                               obtainedAt: Date(timeIntervalSince1970: 0), grade: .common)
        kubfu.growthRate = .mediumFast
        store.addForTesting(kubfu)
        let dto = try! JSONDecoder().decode(ChainDTO.self, from: Data(kubfuChain.utf8))
        let line = EvoLine(baseID: 891, tree: PokeAPIClient.node(from: dto.chain),
                           rarity: .common, names: [:])
        return (store, line)
    }

    @MainActor func testTheScrollDecidesTheStyle() {
        let (store, line) = kubfuStore()
        store.grantForTesting(EvolutionItem.scrollOfWaters)
        let id = store.state.box[0].id
        XCTAssertTrue(store.evolve(individualID: id, to: 892, line: line, using: .scrollOfWaters))
        XCTAssertEqual(store.state.box[0].fixedForm, "rapidstrike")
        XCTAssertEqual(store.state.box[0].spriteForm, "urshifu-rapidstrike")
    }

    @MainActor func testTheDarknessScrollLeavesTheBaseForm() {
        let (store, line) = kubfuStore()
        store.grantForTesting(EvolutionItem.scrollOfDarkness)
        let id = store.state.box[0].id
        XCTAssertTrue(store.evolve(individualID: id, to: 892, line: line, using: .scrollOfDarkness))
        XCTAssertNil(store.state.box[0].fixedForm, "기본형에는 키를 안 박는다")
    }

    /// 요구 집합에 없는 도구로는 진화하지 않는다 — 아무 도구로나 아무 모습이나 만들 수 있게 된다.
    @MainActor func testAnItemOutsideTheRequirementIsRefused() {
        let (store, line) = kubfuStore()
        store.grantForTesting(EvolutionItem.fireStone)
        store.grantForTesting(EvolutionItem.scrollOfWaters)
        XCTAssertFalse(store.evolve(individualID: store.state.box[0].id, to: 892,
                                    line: line, using: .fireStone))
    }

    /// 요구가 여럿인데 안 고르면 실패한다 — 조용히 첫 번째를 쓰면 선택이 사라진다.
    @MainActor func testAChoiceMustBeMadeWhenSeveralItemsQualify() {
        let (store, line) = kubfuStore()
        store.grantForTesting(EvolutionItem.scrollOfWaters)
        XCTAssertFalse(store.evolve(individualID: store.state.box[0].id, to: 892, line: line))
    }

    /// 요구한 도구를 **갖고 있지 않으면** 집합 안의 도구를 골라도 안 된다 — 가진 것으로만 고른다.
    @MainActor func testAChosenItemMustBeOwned() {
        let (store, line) = kubfuStore()
        store.grantForTesting(EvolutionItem.scrollOfDarkness)
        XCTAssertFalse(store.evolve(individualID: store.state.box[0].id, to: 892,
                                    line: line, using: .scrollOfWaters))
        XCTAssertEqual(store.state.box[0].speciesID, 891)
    }

    /// 도구 조건이 아닌 진화에 도구를 넘기면 거부한다 — 호출부가 뭔가 잘못 알고 있는 것이다.
    @MainActor func testAnItemIsRefusedWhereNoItemIsRequired() {
        let (store, _) = kubfuStore()
        store.grantForTesting(EvolutionItem.fireStone)
        let plain = EvoLine(baseID: 891,
                            tree: EvoNode(speciesID: 891, children: [EvoNode(speciesID: 892, children: [])]),
                            rarity: .common, names: [:])
        XCTAssertFalse(store.evolve(individualID: store.state.box[0].id, to: 892,
                                    line: plain, using: .fireStone))
    }

    /// **도감 키는 변종을 박은 뒤에 등록돼야 한다.** 먼저 등록하면 연격이 일격 칸에 들어간다.
    @MainActor func testTheDexRecordsTheResultingForm() {
        let (store, line) = kubfuStore()
        store.grantForTesting(EvolutionItem.scrollOfWaters)
        store.evolve(individualID: store.state.box[0].id, to: 892, line: line, using: .scrollOfWaters)
        XCTAssertTrue(store.state.dexForms.contains(DexKey.key(for: store.state.box[0])))
        XCTAssertTrue(store.state.dexForms.contains("892/urshifu-rapidstrike"))
        XCTAssertFalse(store.state.dexForms.contains("892"), "일격 칸이 같이 켜졌다")
    }

    /// **도감 키는 디코드 경계(`DexKey.sanitized`)를 통과해야 한다.** 메모리의 `dexForms` 만 보면
    /// 후보 목록(`DexKey.candidates`)이 연격을 모를 때도 초록이다 — 다음 기동에서 유령 키로
    /// 지워지고, 박스에 그 개체가 없으면(박사에게 보냈다면) 도감 항목이 영영 사라진다.
    @MainActor func testTheDexKeySurvivesTheStateRoundTrip() throws {
        let (store, line) = kubfuStore()
        store.grantForTesting(EvolutionItem.scrollOfWaters)
        let id = store.state.box[0].id
        store.evolve(individualID: id, to: 892, line: line, using: .scrollOfWaters)
        // 개체를 박스에서 치운다 — 박스 재스캔(`PlayerState` 디코드)이 키를 되살려 주는 경로를 끊는다.
        store.mutate { $0.box.removeAll { $0.id == id } }
        let reloaded = try JSONDecoder().decode(PlayerState.self,
                                                from: JSONEncoder().encode(store.state))
        XCTAssertTrue(reloaded.dexForms.contains("892/urshifu-rapidstrike"),
                      "연격 도감 항목이 디코드에서 지워졌다")
        XCTAssertTrue(DexKey.sanitized(["892/urshifu-rapidstrike"]).contains("892/urshifu-rapidstrike"))
    }

    /// 도감 화면은 후보에서 행을 만든다 — 기본형 + 연격 두 행이어야 칸·진행도·폼 상세가 맞다.
    func testTheDexOffersBothStyles() {
        let rows = DexKey.candidates(speciesID: 892)
        XCTAssertEqual(rows.map(\.key), ["892", "892/urshifu-rapidstrike"])
        XCTAssertNil(rows[0].slug)
        XCTAssertEqual(rows[1].slug, "urshifu-rapidstrike")
        XCTAssertTrue(DexKey.bareKeyIsAPlainBase(speciesID: 892), "옛 세이브의 892 가 원종으로 안 읽힌다")
    }

    /// 대조군 — 기본형은 일격 칸을 켜고 연격 칸은 건드리지 않는다.
    @MainActor func testTheBaseFormFillsTheBaseSlot() {
        let (store, line) = kubfuStore()
        store.grantForTesting(EvolutionItem.scrollOfDarkness)
        store.evolve(individualID: store.state.box[0].id, to: 892, line: line, using: .scrollOfDarkness)
        XCTAssertTrue(store.state.dexForms.contains("892"))
        XCTAssertFalse(store.state.dexForms.contains("892/urshifu-rapidstrike"))
    }

    /// 박힌 모습은 폼이 아니라 고정 변종이라 되돌아가지 않는다.
    @MainActor func testTheFixedFormSurvivesRevertForm() {
        let (store, line) = kubfuStore()
        store.grantForTesting(EvolutionItem.scrollOfWaters)
        let id = store.state.box[0].id
        store.evolve(individualID: id, to: 892, line: line, using: .scrollOfWaters)
        XCTAssertFalse(store.revertForm(individualID: id))
        XCTAssertEqual(store.state.box[0].fixedForm, "rapidstrike")
    }

    /// 배지도 같은 해석기를 지난다 — 부화 카탈로그만 묻으면 연격이 이름 없이 그려진다.
    @MainActor func testTheBadgeNamesTheStyle() {
        let (store, line) = kubfuStore()
        store.grantForTesting(EvolutionItem.scrollOfWaters)
        store.evolve(individualID: store.state.box[0].id, to: 892, line: line, using: .scrollOfWaters)
        XCTAssertEqual(store.state.box[0].birthFormLabel(.en), "Rapid Strike Style")
    }

    /// 두 카탈로그가 같은 종에서 변종 키를 두고 다투면 안 된다.
    func testTheTwoCatalogsDoNotOverlap() {
        for (speciesID, variants) in EvolvedFormCatalog.variantsBySpecies {
            let birth = Set(BirthFormCatalog.forms(speciesID: speciesID).map(\.variant))
            XCTAssertTrue(birth.isDisjoint(with: Set(variants)),
                          "#\(speciesID) 의 변종 키가 겹친다")
        }
    }
}

/// 마빌크는 사탕공예를 들고 진화한다 — 지금은 도구 없이 레벨 20이다(실측).
final class MilceryEvolutionTests: XCTestCase {
    /// `evolution-chain/452` 에서 **사탕공예마다 한 줄씩** 잘라 왔다. 원래 63줄인데 크림 축이
    /// 줄 수만 늘리고 파서가 보는 것은 `held_item` 집합이라, 7줄이면 같은 결과가 나온다.
    private let milceryChain = """
    {"chain": {
      "species": {"name": "milcery", "url": "https://pokeapi.co/api/v2/pokemon-species/868/"},
      "evolution_details": [],
      "evolves_to": [{
        "species": {"name": "alcremie", "url": "https://pokeapi.co/api/v2/pokemon-species/869/"},
        "evolution_details": [
          {"trigger": {"name": "spin"}, "held_item": {"name": "strawberry-sweet"}},
          {"trigger": {"name": "spin"}, "held_item": {"name": "berry-sweet"}},
          {"trigger": {"name": "spin"}, "held_item": {"name": "love-sweet"}},
          {"trigger": {"name": "spin"}, "held_item": {"name": "star-sweet"}},
          {"trigger": {"name": "spin"}, "held_item": {"name": "clover-sweet"}},
          {"trigger": {"name": "spin"}, "held_item": {"name": "flower-sweet"}},
          {"trigger": {"name": "spin"}, "held_item": {"name": "ribbon-sweet"}}],
        "evolves_to": []}]}}
    """

    func testMilceryAsksForASweet() throws {
        let dto = try JSONDecoder().decode(ChainDTO.self, from: Data(milceryChain.utf8))
        let node = try XCTUnwrap(PokeAPIClient.node(from: dto.chain).node(withID: 869))
        guard case .item(let items) = node.requirement else {
            return XCTFail("도구 조건이 아니다: \(node.requirement)")
        }
        XCTAssertEqual(items.count, 7, "\(items)")
        XCTAssertTrue(items.contains(.strawberrySweet))
    }

    func testEverySweetOpensItsOwnLook() {
        let sweets: [EvolutionItem] = [.strawberrySweet, .berrySweet, .loveSweet, .starSweet,
                                       .cloverSweet, .flowerSweet, .ribbonSweet]
        let variants = sweets.map { EvolvedFormCatalog.variant(speciesID: 869, item: $0) }
        XCTAssertEqual(variants.count, Set(variants.map { $0 ?? "(기본)" }).count,
                       "사탕공예 둘이 같은 모습을 연다: \(variants)")
    }

    func testMilceryForagesEverySweet() {
        XCTAssertEqual(Set(ForageCatalog.needs(speciesID: 868, region: nil, fixedForm: nil)).count, 7)
    }

    /// 869 의 레벨 폴백이 남아 있으면 도달 불가 경로다.
    func testTheLevelFallbackIsGone() {
        XCTAssertNil(UnstatedEvolutionCatalog.override(speciesID: 869))
    }

    /// 크림이 디코드 경계(`sanitized()`)에서 벗겨지면 마휘핑이 기동마다 바닐라로 돌아간다 —
    /// 도감 칸은 크림으로 켜진 채라 어긋남이 영구히 남는다(연격 우라오스와 같은 경로).
    /// 여섯 크림 전부를 직접 돌려 본다. 마빌크 단계에 적힌 크림은 여전히 버려야 한다.
    func testEveryCreamSurvivesSanitizing() {
        let creams = ["rubycream", "matchacream", "mintcream", "lemoncream", "saltedcream", "rainbowswirl"]
        XCTAssertEqual(Set(creams), Set(EvolvedFormCatalog.variantsBySpecies[869] ?? []))
        for cream in creams {
            var alcremie = Individual(baseID: 868, speciesID: 869, pathIDs: [868, 869], nature: .brave,
                                      obtainedAt: Date(timeIntervalSince1970: 1), grade: .common)
            alcremie.fixedForm = cream
            XCTAssertEqual(alcremie.sanitized().fixedForm, cream, cream)

            var milcery = Individual(baseID: 868, speciesID: 868, pathIDs: [868], nature: .brave,
                                     obtainedAt: Date(timeIntervalSince1970: 1), grade: .common)
            milcery.fixedForm = cream
            XCTAssertNil(milcery.sanitized().fixedForm, "마빌크에 크림이 남았다: \(cream)")
        }
    }
}

/// 진화로 정해지는 모습의 카탈로그 무결성 — 부화 카탈로그에는 있던 검사(`BirthFormExpansionTests`)가
/// 이쪽에는 없었다. 손으로 적은 슬러그의 오타는 앱이 안 죽어서 빈 그림으로만 드러난다.
final class EvolvedFormCatalogIntegrityTests: XCTestCase {
    /// **모든 슬러그가 종 슬러그 + 폼 접미사 꼴이어야 한다.** 우라오스·마휘핑 모두.
    func testEverySlugBelongsToItsSpecies() {
        var checked = 0
        for row in EvolvedFormCatalog.all {
            guard let slug = row.slug else { continue }
            checked += 1
            guard let base = SpeciesSlug.slug(row.speciesID) else {
                XCTFail("#\(row.speciesID) 의 종 슬러그가 없다"); continue
            }
            XCTAssertTrue(slug == base || slug.hasPrefix(base + "-"),
                          "#\(row.speciesID) 의 \(slug) 이 \(base) 의 폼이 아니다")
            // **접두사 검사만으론 접미사 오타(`alcremie-rubycreem`)를 못 거른다** — 접두사는 맞기 때문이다.
            // 이 카탈로그의 슬러그는 전부 `종-변종` 꼴이므로(Showdown 에서 200 확인한 값이다) 변종 키에서
            // 유도한 값과 정확히 같아야 한다. 슬러그만 틀리면 여기서 걸린다.
            if let variant = row.variant {
                XCTAssertEqual(slug, "\(base)-\(variant)", "#\(row.speciesID) 슬러그가 변종 키와 어긋난다")
            }
        }
        XCTAssertEqual(checked, 7, "슬러그를 가진 행이 일곱이 아니다 — 검사가 비었는지 확인")
    }

    /// 세 언어 이름이 다 있어야 한다 — 하나라도 비면 그 언어에서 배지가 빈칸이 된다.
    func testEveryLabelHasAllThreeLanguages() {
        for row in EvolvedFormCatalog.all {
            guard let label = row.label else { continue }
            for lang in AppLanguage.allCases {
                XCTAssertFalse(label.text(lang).isEmpty,
                               "\(row.variant ?? "?") 의 \(lang) 이름이 비었다")
            }
        }
    }

    /// 마휘핑은 도감에 닿는다 — 기본형 한 행 + 크림 여섯. `FixedForm.forms` 가 진화 카탈로그를
    /// 도감 후보에 "자동으로" 싣는다는 주장의 실제 행사다. 빠지면 `sanitized` 가 크림 키를
    /// 디코드 때 유령으로 지워 도감이 영구히 줄어든다.
    func testAlcremieReachesTheDex() {
        let rows = DexKey.candidates(speciesID: 869)
        XCTAssertEqual(rows.count, 7, "\(rows.map(\.key))")
        XCTAssertEqual(rows.first?.key, "869")
        XCTAssertNil(rows.first?.label, "원종 행에 이름이 붙었다")
        let creams = ["rubycream", "matchacream", "mintcream", "lemoncream", "saltedcream", "rainbowswirl"]
        for cream in creams {
            XCTAssertTrue(rows.contains { $0.key == "869/alcremie-\(cream)" && $0.label != nil },
                          "도감 후보에 \(cream) 가 없다: \(rows.map(\.key))")
        }
        let keys = Set(["869"] + creams.map { "869/alcremie-\($0)" })
        XCTAssertEqual(DexKey.sanitized(keys), keys, "크림 키가 경계에서 지워졌다")
        // 대조군 — 오타 난 키는 여전히 유령이다(필터가 열려 있지 않다).
        XCTAssertEqual(DexKey.sanitized(["869/alcremie-rubycreem"]), [])
    }
}
