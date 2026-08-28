import XCTest
@testable import PokeDexBar

/// 성별 — 부화 시 한 번 정해져 평생 가고, 여섯 갈래의 진화를 가른다.
@MainActor
final class GenderTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeStore() -> PlayerStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("gender-\(UUID().uuidString).json")
        return PlayerStore(fileURL: url, rng: SeededRNG(seed: 1), now: { self.now })
    }

    // MARK: 성비 굴림

    /// 확정 성별은 **굴림과 무관하게 확정**이다. 경계를 정수로 접으면 `rate == 8` 에서
    /// `roll == 1.0` 이 수컷으로 새는데, 그건 "암컷만"이라는 사실을 깨는 것이다.
    func testFixedGendersIgnoreTheRollEntirely() {
        for roll in [0.0, 0.5, 0.999_999, 1.0] {
            XCTAssertEqual(GenderBalance.roll(rate: 8, roll: roll), .female, "굴림 \(roll)")
            XCTAssertEqual(GenderBalance.roll(rate: 0, roll: roll), .male, "굴림 \(roll)")
            XCTAssertEqual(GenderBalance.roll(rate: -1, roll: roll), .genderless, "굴림 \(roll)")
        }
    }

    /// 절반은 절반에서 갈린다 — 경계가 밀리면 성비가 통째로 틀어진다.
    func testTheHalfRateSplitsAtHalf() {
        XCTAssertEqual(GenderBalance.roll(rate: 4, roll: 0.499), .female)
        XCTAssertEqual(GenderBalance.roll(rate: 4, roll: 0.5), .male)
        // 12.5% — 스타터의 성비. 8분의 1 경계.
        XCTAssertEqual(GenderBalance.roll(rate: 1, roll: 0.124), .female)
        XCTAssertEqual(GenderBalance.roll(rate: 1, roll: 0.125), .male)
    }

    /// 범위 밖 성비는 경계에서 기본값으로 잘린다(관대 디코딩의 짝).
    func testABogusRateIsClampedAtTheBoundary() {
        XCTAssertEqual(GenderBalance.sanitizedRate(Int.max), GenderBalance.defaultRate)
        XCTAssertEqual(GenderBalance.sanitizedRate(-99), GenderBalance.defaultRate)
        XCTAssertEqual(GenderBalance.sanitizedRate(-1), -1, "무성별은 유효한 값이라 안 자른다")
        XCTAssertEqual(GenderBalance.sanitizedRate(8), 8)
    }

    // MARK: 부화

    /// 알에 적힌 성비로 부화 시점에 굴린다 — **알에는 성별이 안 적힌다**(확인 전에 새면 안 된다).
    func testGenderIsRolledAtHatchNotStoredOnTheEgg() throws {
        let store = makeStore()
        let egg = try XCTUnwrap(store.placeEgg(grade: .common, speciesID: 1, shiny: false,
                                               genderRate: 8))
        // 알 자체는 성비만 안다.
        XCTAssertEqual(egg.genderRate, 8)
        store.mutate { s in
            for i in s.eggs.indices { s.eggs[i].hatchesAt = self.now }
        }
        let hatched = try XCTUnwrap(store.claimHatch(eggID: egg.id, at: now))
        XCTAssertEqual(hatched.gender, .female, "성비 8(암컷만)인데 수컷이 나왔다")
    }

    /// 무성별 종은 무성별로 태어난다 — `nil`(미배정)과 구분된다.
    func testAGenderlessSpeciesHatchesGenderlessNotNil() throws {
        let store = makeStore()
        let egg = try XCTUnwrap(store.placeEgg(grade: .common, speciesID: 81, shiny: false,
                                               genderRate: GenderBalance.genderless))
        store.mutate { s in
            for i in s.eggs.indices { s.eggs[i].hatchesAt = self.now }
        }
        let hatched = try XCTUnwrap(store.claimHatch(eggID: egg.id, at: now))
        XCTAssertEqual(hatched.gender, .genderless)
        XCTAssertNotNil(hatched.gender, "무성별을 nil 로 적으면 보정이 매번 다시 굴린다")
    }

    /// 스타터도 성별을 갖고 태어난다 — 여기엔 인덱스가 없어서 기본값에 맡기면 영영 안 정해진다.
    func testTheStarterIsBornWithAGender() throws {
        let store = makeStore()
        let starter = try XCTUnwrap(store.chooseStarter(speciesID: 1, grade: .common))
        XCTAssertNotNil(starter.gender, "스타터의 성별이 안 정해졌다")
        XCTAssertNotEqual(starter.gender, .genderless, "스타터 27마리는 전부 성별이 있다")
    }

    // MARK: 옛 세이브 보정

    /// 성별 키가 없는 개체가 그대로 열리고(박스가 안 비고), 라인이 오면 채워진다.
    func testAnOldIndividualDecodesThenGetsBackfilled() throws {
        let json = """
        {"baseID": 1, "speciesID": 1, "nature": "hardy", "grade": "common"}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Individual.self, from: json)
        XCTAssertNil(decoded.gender, "성별 없는 세이브는 nil 로 열려야 한다(개체를 버리면 안 된다)")

        let store = makeStore()
        store.mutate { $0.box = [decoded] }
        let line = EvoLine(baseID: 1, tree: EvoNode(speciesID: 1, children: []),
                           rarity: .common, names: [:], genderRates: [1: 4])
        store.backfillGenders(from: line)
        XCTAssertNotNil(store.state.box[0].gender, "보정이 성별을 안 채웠다")
    }

    /// **보정은 이미 있는 성별을 절대 다시 굴리지 않는다.** 다시 굴리면 켤 때마다 성별이 바뀌고
    /// 성별 진화가 그때그때 달라진다.
    func testBackfillNeverRerollsAGenderItAlreadyHas() {
        let store = makeStore()
        var male = Individual(baseID: 1, speciesID: 1, pathIDs: [1], gender: .male,
                              nature: .hardy, obtainedAt: now, grade: .common)
        male.id = UUID(uuidString: "00000000-0000-0000-0000-0000000000FF")!
        store.mutate { $0.box = [male] }
        // 성비 8(암컷만)로 보정을 돌려도 이미 정해진 수컷은 안 바뀐다.
        let line = EvoLine(baseID: 1, tree: EvoNode(speciesID: 1, children: []),
                           rarity: .common, names: [:], genderRates: [1: 8])
        store.backfillGenders(from: line)
        XCTAssertEqual(store.state.box[0].gender, .male, "이미 있는 성별을 다시 굴렸다")
    }

    /// 보정 굴림은 개체 id 에서 나오므로 몇 번을 돌려도 같다(난수기를 쓰면 기기마다 갈린다).
    func testTheBackfillRollIsStableForTheSameIndividual() {
        let id = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let first = PlayerStore.stableUnit(from: id)
        XCTAssertEqual(first, PlayerStore.stableUnit(from: id))
        XCTAssertNotEqual(first, PlayerStore.stableUnit(from: UUID()))
        XCTAssertTrue((0..<1).contains(first), "0…1 밖으로 나가면 굴림이 아니다")
    }

    // MARK: 성별로 갈리는 진화 (여섯 갈래)

    /// 눈꼬마(361) — 암컷만 눈여아(478)가 된다. 수컷은 눈설왕(460)만.
    func testOnlyAFemaleSnoruntCanBecomeFroslass() {
        let store = makeStore()
        // 새벽의돌 갈래(눈여아)와 레벨 갈래(눈설왕)를 함께 둔 트리.
        let tree = EvoNode(speciesID: 361, children: [
            EvoNode(speciesID: 460, children: [], requirementRaw: .level(42)),
            EvoNode(speciesID: 478, children: [], requirementRaw: .level(42),
                    requiredGender: .female),
        ])
        let line = EvoLine(baseID: 361, tree: tree, rarity: .common, names: [:])

        let female = Individual(baseID: 361, speciesID: 361, pathIDs: [361], gender: .female,
                                nature: .hardy, obtainedAt: now, grade: .common)
        XCTAssertEqual(Set(store.evolutionChoices(female, line: line)), [460, 478])

        let male = Individual(baseID: 361, speciesID: 361, pathIDs: [361], gender: .male,
                              nature: .hardy, obtainedAt: now, grade: .common)
        XCTAssertEqual(store.evolutionChoices(male, line: line), [460],
                       "수컷 눈꼬마가 눈여아가 된다")
    }

    /// 성별을 아직 모르는 개체는 제한 있는 갈래가 막힌다 — 열어 두면 되돌릴 수 없는 진화를 한다.
    func testAnUnknownGenderCannotTakeAGatedBranch() {
        let store = makeStore()
        let tree = EvoNode(speciesID: 361, children: [
            EvoNode(speciesID: 460, children: [], requirementRaw: .level(42)),
            EvoNode(speciesID: 478, children: [], requirementRaw: .level(42),
                    requiredGender: .female),
        ])
        let line = EvoLine(baseID: 361, tree: tree, rarity: .common, names: [:])
        let unknown = Individual(baseID: 361, speciesID: 361, pathIDs: [361],
                                 nature: .hardy, obtainedAt: now, grade: .common)
        XCTAssertNil(unknown.gender)
        XCTAssertEqual(store.evolutionChoices(unknown, line: line), [460],
                       "성별을 모르는데 암컷 전용 갈래가 열렸다")
    }

    /// 제한이 없는 갈래는 성별과 무관하게 늘 열린다(게이트가 전부를 막고 있지 않은지 — 대조군).
    func testAnUngatedBranchStaysOpenForEveryGender() {
        let store = makeStore()
        let tree = EvoNode(speciesID: 1, children: [
            EvoNode(speciesID: 2, children: [], requirementRaw: .level(16)),
        ])
        let line = EvoLine(baseID: 1, tree: tree, rarity: .common, names: [:])
        for gender in [Gender.male, .female, .genderless] {
            let individual = Individual(baseID: 1, speciesID: 1, pathIDs: [1], gender: gender,
                                        nature: .hardy, obtainedAt: now, grade: .common)
            XCTAssertEqual(store.evolutionChoices(individual, line: line), [2],
                           "\(gender) 가 제한 없는 갈래에서 막혔다")
        }
    }

    /// 성별 제한이 트리를 다시 만드는 자리(`keepingSupportedSpecies`)에서 새지 않는다 —
    /// 여기서 새면 **모든 라인에서** 새고, 수컷 눈꼬마가 눈여아가 된다.
    func testTheGenderGateSurvivesTreePruning() throws {
        let tree = EvoNode(speciesID: 361, children: [
            EvoNode(speciesID: 478, children: [], requirementRaw: .level(42),
                    requiredGender: .female),
        ])
        // EvoLine.init 이 항상 keepingSupportedSpecies 를 지난다.
        let line = EvoLine(baseID: 361, tree: tree, rarity: .common, names: [:])
        let node = try XCTUnwrap(line.tree.node(withID: 478))
        XCTAssertEqual(node.requiredGender, .female, "가지치기가 성별 제한을 떨어뜨렸다")
    }

    /// API 응답의 성별 코드가 올바로 읽힌다(1=암컷, 2=수컷, 없으면 제한 없음).
    func testTheAPIGenderCodeMapsCorrectly() {
        func detail(_ gender: Int?) -> [EvolutionDetail] {
            [EvolutionDetail(trigger: nil, item: nil, held_item: nil, min_happiness: nil,
                             min_level: nil, gender: gender)]
        }
        XCTAssertEqual(PokeAPIClient.gender(from: detail(1)), .female)
        XCTAssertEqual(PokeAPIClient.gender(from: detail(2)), .male)
        XCTAssertNil(PokeAPIClient.gender(from: detail(nil)))
        XCTAssertNil(PokeAPIClient.gender(from: nil))
    }

    // MARK: 그림과 도감

    /// 암컷 그림은 **실측한 98종에만** 붙는다. 없는 종에 붙이면 그 칸이 통째로 빈다.
    func testFemaleSlugsOnlyExistForMeasuredSpecies() {
        XCTAssertEqual(GenderSpriteCatalog.femaleSprite.count, 98)
        XCTAssertEqual(GenderSpriteCatalog.femaleSlug(25), "pikachu-f")
        XCTAssertNil(GenderSpriteCatalog.femaleSlug(1), "이상해씨엔 암컷 그림이 없다")
        // 폼으로 세는 넷은 모두 그림이 있는 종의 부분집합이어야 한다.
        XCTAssertTrue(GenderSpriteCatalog.formSpecies.isSubset(of: GenderSpriteCatalog.femaleSprite))
    }

    /// **지방 모습이 암컷 그림을 이긴다** — `raichu-alola-f` 는 존재하지 않아서, 여기서
    /// 가로채면 알로라 라이츄의 그림이 사라진다.
    func testARegionalFormBeatsTheFemaleSprite() {
        var alolan = Individual(baseID: 172, speciesID: 26, pathIDs: [26], gender: .female,
                                nature: .hardy, obtainedAt: now, grade: .common)
        alolan.region = .alola
        XCTAssertEqual(alolan.spriteForm, "raichu-alola")

        var plain = Individual(baseID: 172, speciesID: 26, pathIDs: [26], gender: .female,
                               nature: .hardy, obtainedAt: now, grade: .common)
        plain.region = nil
        XCTAssertEqual(plain.spriteForm, "raichu-f")
    }

    /// 도감은 **폼으로 세는 넷만** 나눈다 — 나머지 94종은 겉모습 차이라 한 칸을 공유한다.
    func testOnlyTheFourFormSpeciesSplitTheDex() {
        func key(_ id: Int, _ gender: Gender) -> String {
            DexKey.key(for: Individual(baseID: id, speciesID: id, pathIDs: [id], gender: gender,
                                       nature: .hardy, obtainedAt: now, grade: .common))
        }
        // 냐오닉스 — 본가도 별개 폼이라 도감이 갈린다.
        XCTAssertEqual(key(678, .female), "678/meowstic-f")
        XCTAssertEqual(key(678, .male), "678")
        // 피카츄 — 하트 꼬리 하나로 두 번 모으게 하지 않는다.
        XCTAssertEqual(key(25, .female), "25")
        XCTAssertEqual(key(25, .male), "25")
    }
}
