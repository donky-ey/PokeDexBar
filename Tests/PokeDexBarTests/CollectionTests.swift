import XCTest
@testable import PokeDexBar

/// 컬렉션 — 주제별 수집 세트. 배지는 도감에서 파생되고, 보상 수령이 세트마다 한 번 있다.
@MainActor
final class CollectionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeStore() -> PlayerStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("coll-\(UUID().uuidString).json")
        return PlayerStore(fileURL: url, rng: SeededRNG(seed: 1), now: { self.now })
    }

    private func seedDex(_ store: PlayerStore, species: any Sequence<Int>) {
        store.mutate { s in
            for id in species { s.dexForms.insert(String(id)) }
        }
    }

    // MARK: 카탈로그

    /// id·구성원이 성하다 — id 유일, 종 번호는 도감 범위 안, 세트 안 중복 없음.
    func testTheCatalogIsSound() {
        let ids = CollectionCatalog.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "세트 id 가 겹친다")
        for entry in CollectionCatalog.all {
            XCTAssertFalse(entry.speciesIDs.isEmpty, "\(entry.id) 가 비었다")
            XCTAssertEqual(entry.speciesIDs.count, Set(entry.speciesIDs).count,
                           "\(entry.id) 안에 같은 종이 두 번 있다")
            XCTAssertTrue(entry.speciesIDs.allSatisfy { (1...1025).contains($0) },
                          "\(entry.id) 에 도감 밖 번호가 있다")
            // 모든 세트가 뭔가를 준다(사용자 결정 — "경험치 사탕이라도"). 빈 배열이면
            // 받기 버튼이 눌리는데 아무 일도 안 일어난다.
            XCTAssertFalse(entry.rewards.isEmpty, "\(entry.id) 의 보상이 비었다")
            for lang in AppLanguage.allCases {
                XCTAssertNotEqual(CollectionCatalog.label(entry.id, lang), entry.id,
                                  "\(entry.id) 의 \(lang) 이름이 없다")
            }
        }
    }

    /// **반짝사탕은 컬렉션 보상에 못 온다.** 미션 쪽 희소성 가드(총 6개)와 별개 경로로
    /// 새면 그 가드가 장식이 된다.
    func testNoShinyCandyLeaksThroughCollections() {
        for entry in CollectionCatalog.all {
            for reward in entry.rewards {
                if case .item(.shinyCandy, _) = reward {
                    XCTFail("\(entry.id) 가 반짝사탕을 준다 — 희소성 가드를 우회한다")
                }
            }
        }
    }

    /// 알려진 세트 몇 개 — 전승 구성을 잠근다(표가 밀리면 여기서 걸린다).
    func testKnownSetsMatchTheLore() throws {
        let clone = try XCTUnwrap(CollectionCatalog.all.first { $0.id == "clone-truth" })
        XCTAssertEqual(Set(clone.speciesIDs), [132, 150, 151], "뮤·뮤츠·메타몽이어야 한다")
        let eevee = try XCTUnwrap(CollectionCatalog.all.first { $0.id == "eevee-friends" })
        XCTAssertEqual(eevee.speciesIDs.count, 9, "이브이 + 진화형 8종이어야 한다")
        XCTAssertTrue(eevee.speciesIDs.contains(700), "님피아가 빠졌다")
        let ub = try XCTUnwrap(CollectionCatalog.all.first { $0.id == "ultra-beasts" })
        XCTAssertEqual(ub.speciesIDs.count, 11)
        // 화석 — 여섯 세대 25종(복원 라인 포함). 세대를 하나 빼먹으면 여기서 걸린다.
        let fossils = try XCTUnwrap(CollectionCatalog.all.first { $0.id == "fossils" })
        XCTAssertEqual(fossils.speciesIDs.count, 25)
        XCTAssertTrue(fossils.speciesIDs.contains(142), "프테라가 빠졌다")
        XCTAssertTrue(fossils.speciesIDs.contains(880), "8세대 화석이 빠졌다")
        // 600족 — 최종 진화형만. 미뇽(147)이 들어오면 이름이 거짓말이 된다.
        let pseudo = try XCTUnwrap(CollectionCatalog.all.first { $0.id == "pseudo-legendaries" })
        XCTAssertEqual(pseudo.speciesIDs.count, 10)
        XCTAssertTrue(pseudo.speciesIDs.contains(149))
        XCTAssertFalse(pseudo.speciesIDs.contains(147), "600족에 미진화형이 들어왔다")
        // 파라독스 — 고대와 미래는 겹치지 않는다(본가 구분 그대로).
        let past = try XCTUnwrap(CollectionCatalog.all.first { $0.id == "paradox-past" })
        let future = try XCTUnwrap(CollectionCatalog.all.first { $0.id == "paradox-future" })
        XCTAssertEqual(past.speciesIDs.count, 10)
        XCTAssertEqual(future.speciesIDs.count, 10)
        XCTAssertTrue(Set(past.speciesIDs).isDisjoint(with: future.speciesIDs),
                      "고대와 미래가 겹친다")
        XCTAssertTrue(future.speciesIDs.contains(1006), "테츠노브지나(미래)가 빠졌다")
    }

    // MARK: 진행과 배지

    /// 배지는 도감에서 파생된다 — 수령 없이 완성 즉시 켜진다. 보상(사탕)은 따로 한 번 받는다.
    func testTheBadgeDerivesFromTheDex() {
        let store = makeStore()
        seedDex(store, species: [144, 145])
        var status = store.collectionStatuses().first { $0.id == "legendary-birds" }!
        XCTAssertEqual(status.done, 2)
        XCTAssertFalse(status.completed)
        XCTAssertFalse(store.canClaimCollection(status.collection), "다 안 모았는데 받아진다")

        seedDex(store, species: [146])
        status = store.collectionStatuses().first { $0.id == "legendary-birds" }!
        XCTAssertTrue(status.completed)
        // 전승 세트도 이제 보상이 있다(사용자 결정) — 완성 즉시 받을 수 있어야 한다.
        XCTAssertTrue(status.claimable)
        XCTAssertTrue(store.claimCollection(status.collection))
        XCTAssertEqual(store.count(of: .expCandy), 20, "전승 세트의 사탕이 안 들어왔다")
    }

    /// 확정권을 주는 세트 — 완성 전엔 못 받고, 받으면 가방에 담기고, 두 번은 못 받는다.
    func testARewardSetClaimsOnceIntoTheBag() throws {
        let store = makeStore()
        let beasts = try XCTUnwrap(CollectionCatalog.all.first { $0.id == "ultra-beasts" })
        seedDex(store, species: beasts.speciesIDs.dropLast())
        XCTAssertFalse(store.claimCollection(beasts), "다 안 모았는데 받아진다")

        seedDex(store, species: beasts.speciesIDs)
        XCTAssertTrue(store.claimCollection(beasts))
        XCTAssertEqual(store.count(of: ShopItem.legendaryEggTicket), 1, "확정권이 안 들어왔다")
        XCTAssertFalse(store.claimCollection(beasts), "같은 세트를 두 번 받는다")
        XCTAssertEqual(store.count(of: ShopItem.legendaryEggTicket), 1)
    }

    /// 레지 패밀리 — 다섯 기둥을 모으면 **레지기가스가 깨어나** 박스와 도감에 합류한다.
    /// 알에서는 안 나오는 종이라(`EggBalance.rewardOnlySpecies`) 이 경로가 유일한 입수처다.
    func testTheRegiFamilyAwakensRegigigas() throws {
        let store = makeStore()
        let regis = try XCTUnwrap(CollectionCatalog.all.first { $0.id == "regi-family" })
        // 레지기가스(486)는 구성원이 아니라 **보상**이다 — 구성원이면 완성이 불가능해진다.
        XCTAssertEqual(Set(regis.speciesIDs), [377, 378, 379, 894, 895])
        seedDex(store, species: [377, 378, 379, 894])
        XCTAssertFalse(store.claimCollection(regis), "다 안 모았는데 깨어난다")

        seedDex(store, species: [895])
        XCTAssertTrue(store.claimCollection(regis))
        let gigas = try XCTUnwrap(store.state.box.first { $0.speciesID == 486 },
                                  "레지기가스가 박스에 없다")
        XCTAssertEqual(gigas.grade, .legendary)
        XCTAssertEqual(gigas.growthRate, .slow)
        XCTAssertTrue(store.state.dex.contains(486), "도감에 등록이 안 됐다")
        XCTAssertFalse(store.claimCollection(regis), "두 번 깨어난다")
        XCTAssertEqual(store.state.box.count(where: { $0.speciesID == 486 }), 1)
    }

    /// 수령 기록이 저장을 오간다.
    func testClaimsSurviveAReload() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("coll-reload-\(UUID().uuidString).json")
        let store = PlayerStore(fileURL: url, rng: SeededRNG(seed: 1), now: { self.now })
        let eevee = try XCTUnwrap(CollectionCatalog.all.first { $0.id == "eevee-friends" })
        seedDex(store, species: eevee.speciesIDs)
        XCTAssertTrue(store.claimCollection(eevee))

        let back = PlayerStore(fileURL: url, rng: SeededRNG(seed: 1), now: { self.now })
        XCTAssertTrue(back.state.claimedCollections.contains("eevee-friends"),
                      "수령 기록이 저장에서 사라진다 — 재수령 구멍")
    }

    /// 컬렉션 키가 없는 기존 세이브가 그대로 열린다.
    func testAnOldSaveWithoutTheKeyDecodes() throws {
        let json = """
        {"earnedTokens": 5}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(PlayerState.self, from: json)
        XCTAssertTrue(decoded.claimedCollections.isEmpty)
    }
}

/// 새로 더한 세트들 — 세대별 스타터와 동물 묶음.
@MainActor
final class NewCollectionTests: XCTestCase {
    /// 스타터 세트는 **세대마다 하나씩 아홉 종**이고, 그 아홉은 연속된 번호다(본가의 배치).
    /// 하나라도 어긋나면 다른 종이 섞여 들어간 것이다.
    func testEveryGenerationHasANineSpeciesStarterSet() {
        let starts = ["kanto": 1, "johto": 152, "hoenn": 252, "sinnoh": 387, "unova": 495,
                      "kalos": 650, "alola": 722, "galar": 810, "paldea": 906]
        for (region, start) in starts {
            let id = "\(region)-starters"
            guard let set = CollectionCatalog.all.first(where: { $0.id == id }) else {
                return XCTFail("\(id) 세트가 없다")
            }
            XCTAssertEqual(set.speciesIDs, Array(start..<(start + 9)), "\(id) 가 연속 9종이 아니다")
        }
        XCTAssertEqual(CollectionCatalog.all.count { $0.id.hasSuffix("-starters") }, 9,
                       "세대는 아홉인데 스타터 세트 수가 다르다")
    }

    /// 동물 세트는 **진화 라인이 끊기면 안 된다** — genus 는 라인 중간에서 말이 바뀌므로
    /// (불꽃숭이=Chimp, 초염몽=Flame) 씨앗만 담으면 이어지는 단계가 빠진다.
    func testAnimalSetsKeepWholeEvolutionLines() {
        let lines: [String: [[Int]]] = [
            "monkeys": [[56, 57, 979], [287, 288, 289], [390, 391, 392],
                        [511, 512], [513, 514], [515, 516], [810, 811, 812], [944, 945]],
            "cats": [[52, 53], [300, 301], [431, 432], [677, 678],
                     [725, 726, 727], [906, 907, 908]],
            "dogs": [[58, 59], [209, 210], [228, 229], [261, 262], [506, 507, 508],
                     [744, 745], [835, 836], [926, 927], [971, 972]],
        ]
        for (id, expected) in lines {
            guard let set = CollectionCatalog.all.first(where: { $0.id == id }) else {
                return XCTFail("\(id) 세트가 없다")
            }
            for line in expected {
                for species in line {
                    XCTAssertTrue(set.speciesIDs.contains(species),
                                  "\(id): \(line) 라인의 \(species) 가 빠졌다")
                }
            }
        }
    }

    /// **경계 멤버는 뺐다**(사용자 결정) — 쟝고는 genus 가 "Cat Ferret" 이지만 몽구스이고,
    /// 자루도는 환상이라 세트 난도를 통째로 올린다. 시비꼬는 앵무라 지방새 자리가 아니다.
    func testBorderlineMembersStayOut() {
        let excluded = [("cats", 335), ("monkeys", 893), ("route-birds", 931)]
        for (id, species) in excluded {
            let set = CollectionCatalog.all.first { $0.id == id }
            XCTAssertFalse(set?.speciesIDs.contains(species) ?? true,
                           "\(id) 에 경계 멤버 \(species) 가 들어 있다")
        }
    }

    /// 팔데아의 지방새는 찌리비 쪽이다 — 대조군. 없으면 "동네새를 다 뺐다" 도 위를 통과한다.
    func testTheRouteBirdSetStillCoversEveryGeneration() throws {
        let set = try XCTUnwrap(CollectionCatalog.all.first { $0.id == "route-birds" })
        for first in [16, 163, 276, 396, 519, 661, 731, 821, 940] {
            XCTAssertTrue(set.speciesIDs.contains(first), "\(first) 세대의 동네새가 빠졌다")
        }
    }

    /// 새 세트도 기존 규율을 지킨다 — 이름이 세 언어에 있고, 종이 안 겹치고, 범위 안이다.
    func testEveryNewSetIsWellFormed() {
        for set in CollectionCatalog.all {
            XCTAssertEqual(Set(set.speciesIDs).count, set.speciesIDs.count,
                           "\(set.id) 에 같은 종이 두 번 있다")
            XCTAssertFalse(set.speciesIDs.isEmpty, "\(set.id) 가 비어 있다")
            for species in set.speciesIDs {
                XCTAssertTrue((1...1025).contains(species), "\(set.id) 의 \(species) 가 범위 밖")
            }
            for lang in AppLanguage.allCases {
                let label = CollectionCatalog.label(set.id, lang)
                XCTAssertNotEqual(label, set.id, "\(set.id) 의 \(lang) 이름이 없다")
                XCTAssertFalse(label.isEmpty)
            }
        }
    }
}

/// 전설·환상이 집을 갖는가 — 컬렉션이 전설 목록을 훑어 만들어지지 않아 뒤 세대일수록 비던 공백.
@MainActor
final class LegendaryCoverageTests: XCTestCase {
    /// 도감 플래그로 뽑은 전설·환상 94종(2026-09 확인). 앱은 이 플래그를 로컬에 안 들고 있어서
    /// 여기 고정한다 — **이 목록이 이 테스트의 증거**이므로, 종이 늘면 같이 갱신한다.
    private let legendaries: Set<Int> = [
        144, 145, 146, 150, 151, 243, 244, 245, 249, 250, 251,
        377, 378, 379, 380, 381, 382, 383, 384, 385, 386,
        480, 481, 482, 483, 484, 485, 486, 487, 488, 489, 490, 491, 492, 493, 494,
        638, 639, 640, 641, 642, 643, 644, 645, 646, 647, 648, 649,
        716, 717, 718, 719, 720, 721,
        772, 773, 785, 786, 787, 788, 789, 790, 791, 792, 793, 794, 795, 796, 797,
        798, 799, 800, 801, 802, 803, 804, 805, 806, 807, 808, 809,
        888, 889, 890, 891, 892, 893, 894, 895, 896, 897, 898, 905,
        1001, 1002, 1003, 1004, 1007, 1008, 1014, 1015, 1016, 1017, 1024, 1025,
    ]

    private var claimed: Set<Int> {
        Set(CollectionCatalog.all.flatMap(\.speciesIDs))
    }

    /// **레지기가스와 히드런만 남는다.** 레지기가스는 레지 세트의 *보상*이라 구성원이 아니고
    /// (그게 유일한 입수처다), 히드런은 원작에서도 짝이 없는 외톨이라 억지로 묶지 않았다.
    /// 그 둘 말고 집이 없는 전설이 새로 생기면 이 테스트가 알린다.
    func testEveryLegendaryHasACollectionExceptTheTwoKnownLoners() {
        let homeless = legendaries.subtracting(claimed).sorted()
        XCTAssertEqual(homeless, [485, 486], "집 없는 전설이 늘었다: \(homeless)")
    }

    /// 세대가 뒤로 갈수록 비던 것이 이 공백의 정체다 — 세대별로도 0이 아닌지 본다.
    /// 대조군 없이 전체 합계만 보면 한 세대가 통째로 비어도 통과한다.
    func testNoGenerationIsLeftEmpty() {
        let ranges = [1: 1...151, 2: 152...251, 3: 252...386, 4: 387...493, 5: 494...649,
                      6: 650...721, 7: 722...809, 8: 810...905, 9: 906...1025]
        for (generation, range) in ranges {
            let inGen = legendaries.filter(range.contains)
            guard !inGen.isEmpty else { continue }
            let covered = inGen.filter(claimed.contains).count
            XCTAssertGreaterThan(covered, inGen.count / 2,
                                 "\(generation)세대 전설 \(inGen.count)마리 중 \(covered)마리만 집이 있다")
        }
    }

    /// 키타카미 세트는 **오거폰을 포함한다** — 사용자 결정. 도감만 보면 독사슬로 묶이는 건
    /// 복숭악동과 수하 셋뿐이지만, 오거폰을 빼면 그 이야기의 주인공이 사라진다.
    func testTheKitakamiSetKeepsOgerpon() throws {
        let set = try XCTUnwrap(CollectionCatalog.all.first { $0.id == "kitakami-legend" })
        XCTAssertTrue(set.speciesIDs.contains(1017), "오거폰이 빠졌다")
        XCTAssertEqual(Set(set.speciesIDs), [1014, 1015, 1016, 1017, 1025])
        // 상자 전설 쪽에는 없다 — 두 세트가 오거폰을 두고 다투면 배치의 뜻이 흐려진다.
        let box = try XCTUnwrap(CollectionCatalog.all.first { $0.id == "paldea-box-legends" })
        XCTAssertFalse(box.speciesIDs.contains(1017))
    }

    /// 환상 세트는 도감이 환상으로 표시한 23종 전부여야 한다 — 하나라도 빠지면 영영 못 채운다.
    func testTheMythicalSetHoldsEveryMythical() throws {
        let mythicals: Set<Int> = [151, 251, 385, 386, 489, 490, 491, 492, 493, 494,
                                   647, 648, 649, 719, 720, 721, 801, 802, 807, 808,
                                   809, 893, 1025]
        let set = try XCTUnwrap(CollectionCatalog.all.first { $0.id == "mythicals" })
        XCTAssertEqual(Set(set.speciesIDs), mythicals)
    }
}
