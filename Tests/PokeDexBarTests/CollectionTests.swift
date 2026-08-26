import XCTest
@testable import PokeDexBar

/// 컬렉션 — 주제별 수집 세트. 배지는 도감에서 파생되고, 보상 있는 세트만 수령이 있다.
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
            for reward in entry.rewards ?? [] {
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
    }

    // MARK: 진행과 배지

    /// 배지는 도감에서 파생된다 — 수령 없이 완성 즉시 켜진다.
    func testTheBadgeDerivesFromTheDex() {
        let store = makeStore()
        seedDex(store, species: [144, 145])
        var status = store.collectionStatuses().first { $0.id == "legendary-birds" }!
        XCTAssertEqual(status.done, 2)
        XCTAssertFalse(status.completed)

        seedDex(store, species: [146])
        status = store.collectionStatuses().first { $0.id == "legendary-birds" }!
        XCTAssertTrue(status.completed)
        // 보상이 없는 세트 — 완성해도 받을 것이 없다.
        XCTAssertFalse(status.claimable)
        XCTAssertFalse(store.claimCollection(status.collection), "배지만인 세트를 수령했다")
        // 판정 함수도 직접 잠근다 — `claimCollection` 의 이중 방어(rewards 언랩)에 가려
        // 판정만 풀리는 회귀가 화면의 죽은 받기 버튼으로 샐 수 있다.
        XCTAssertFalse(store.canClaimCollection(status.collection))
    }

    /// 보상 있는 세트 — 완성 전엔 못 받고, 받으면 가방에 담기고, 두 번은 못 받는다.
    func testARewardSetClaimsOnceIntoTheBag() throws {
        let store = makeStore()
        let regis = try XCTUnwrap(CollectionCatalog.all.first { $0.id == "regi-family" })
        seedDex(store, species: [377, 378, 379, 486, 894])
        XCTAssertFalse(store.claimCollection(regis), "다 안 모았는데 받아진다")

        seedDex(store, species: [895])
        XCTAssertTrue(store.claimCollection(regis))
        XCTAssertEqual(store.count(of: ShopItem.legendaryEggTicket), 1, "확정권이 안 들어왔다")
        XCTAssertFalse(store.claimCollection(regis), "같은 세트를 두 번 받는다")
        XCTAssertEqual(store.count(of: ShopItem.legendaryEggTicket), 1)
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
