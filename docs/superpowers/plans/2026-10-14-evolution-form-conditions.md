# 진화 조건·결과가 무엇에 따라 갈리는가 — 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 진화 조건이 **태생 모습에 따라 갈리게** 하고(결함 수정), **쓴 도구가 결과 모습을 정하게** 한다(신규).

**Architecture:** 조건은 `EvoNode` 에 세 갈래로 담긴다 — 기본(`requirementRaw`), 지방(`regionalRequirementRaw`, 건드리지 않음), 태생 모습별(`formRequirementsRaw`, 신규). 조회는 개체의 `region`·`fixedForm` 으로 고른다. 결과 모습은 새 enum 필드가 아니라 **이미 있는 고정 변종 저장소**(`Individual.birthForm` → `fixedForm` 으로 개명, 저장 키는 유지)에 박고, 두 카탈로그(`BirthFormCatalog`·`EvolvedFormCatalog`)를 `FixedForm.resolve` 한 자리에서 묻는다.

**Tech Stack:** Swift 5.9 / SwiftUI / XCTest. 외부 데이터는 PokéAPI(REST), 스프라이트는 Showdown.

**Spec:** [docs/superpowers/specs/2026-10-14-evolution-form-conditions-design.md](../specs/2026-10-14-evolution-form-conditions-design.md)

## Global Constraints

- **커밋 메시지는 영어.** PR 제목·본문도 영어만(`CLAUDE.md` §기여 언어 규약). `Co-Authored-By: Claude` 트레일러를 **붙이지 않는다**(사용자 전역 지침).
- **테스트는 네트워크를 타지 않는다.** 픽스처는 커밋된 것만 읽는다(test-gate 오프라인).
- **픽스처는 실제 응답에서 잘라 온다.** 손으로 쓰지 않는다 — 픽스처가 파서와 같은 오해를 공유하면 둘 다 틀린 채로 통과한다(`CLAUDE.md`).
- **고유명사 라벨은 공식 이름표에서 받는다.** 생성 스크립트 + 픽스처 + 오프라인 대조(`ItemNameTests` 패턴).
- **세이브 저장 키를 바꾸지 않는다.** 속성명은 바꿔도 `CodingKeys` 는 유지한다.
- **지방 조건 경로(`regionalRequirementRaw`·`isRegional`)는 건드리지 않는다.** 두 번 틀렸던 자리다.
- 기존 전체 테스트 1617개가 계속 통과해야 한다: `swift test`.

## Review Focus

1. **옛 세이브의 `fixedForm` 이 nil 인 데인차·차데스** — 변종 키가 없으므로 **기본형 조건**(깨진포트·범작찻잔)이 걸려야 한다. 모습별 맵을 먼저 보되 키가 없으면 기본으로 떨어지는지. → Task 2
2. **`evolve(using:)` 에 요구 집합 밖의 도구를 넘기는 경우** — 거부해야 한다. 안 그러면 아무 도구로나 아무 모습이나 만들 수 있다. → Task 5
3. **`evolve` 안에서 도감 키를 등록하는 순서** — `dexForms.insert(DexKey.key(for:))` 가 `fixedForm` 을 박기 **전에** 불리면 연격 우라오스가 일격 칸에 들어간다. → Task 5
4. **도구 이름을 하나도 못 알아본 갈래** — `.item([])` 을 만들면 `.none` 이 되어 조건 없이 진화한다. 아는 것이 하나도 없으면 집합을 **만들지 않고** 기존 폴백(레벨)으로 떨어져야 한다. → Task 4
5. **종 이름에 하이픈이 있는 종**(`mr-mime-galar`·`jangmo-o`) — `required_pokemon_form` 에서 변종 키를 뽑을 때 첫 하이픈으로 자르면 깨진다. 부모 종의 **알려진 변종 키와 접미사로 대조**해야 한다. → Task 1

---

### Task 1: 조건을 태생 모습별로 가르는 파서

**Files:**
- Modify: `Sources/PokeDexBar/Core/CompanionModel.swift:71-110` (`EvoNode`)
- Modify: `Sources/PokeDexBar/Core/PokeAPIClient.swift:315-331` (`node(from:)`), `:357-389` (`requirement`)
- Test: `Tests/PokeDexBarTests/EvolutionItemTests.swift` (새 클래스 추가)

**Interfaces:**
- Consumes: `BirthFormCatalog.forms(speciesID:) -> [BirthForm]`, `EvolutionDetail.required_pokemon_form`
- Produces: `EvoNode.formRequirementsRaw: [String: EvoRequirementRaw]`, `PokeAPIClient.formVariantKey(_ detail: EvolutionDetail, parentSpeciesID: Int) -> String?`, `PokeAPIClient.node(from:parentLevel:parentSpeciesID:)`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`Tests/PokeDexBarTests/EvolutionItemTests.swift` 끝에 추가. 픽스처는 `evolution-chain/449`·`539` 에서 잘라 온 것이다(2026-10-14 캡처).

```swift
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
        XCTAssertEqual(node.requirementRaw, .item("cracked-pot"),
                       "위작(기본)이 깨진포트를 요구하지 않는다")
    }

    func testTheRareVariantGetsItsOwnRequirement() throws {
        let dto = try JSONDecoder().decode(ChainDTO.self, from: Data(sinisteaChain.utf8))
        let node = try XCTUnwrap(PokeAPIClient.node(from: dto.chain).node(withID: 855))
        XCTAssertEqual(node.formRequirementsRaw["antique"], .item("chipped-pot"),
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
        XCTAssertEqual(node.requirementRaw, .item("water-stone"))
        XCTAssertTrue(node.formRequirementsRaw.isEmpty, "\(node.formRequirementsRaw)")
    }

    /// 종 이름에 하이픈이 있어도 변종 키를 바르게 뽑는다 — 첫 하이픈으로 자르면 깨진다.
    func testVariantKeysSurviveHyphenatedSpeciesNames() {
        let detail = PokeAPIClient.detailForTesting(requiredForm: "sinistea-antique")
        XCTAssertEqual(PokeAPIClient.formVariantKey(detail, parentSpeciesID: 854), "antique")
        let unrelated = PokeAPIClient.detailForTesting(requiredForm: "eevee-starter")
        XCTAssertNil(PokeAPIClient.formVariantKey(unrelated, parentSpeciesID: 133))
    }
}
```

- [ ] **Step 2: 실패를 확인한다**

Run: `swift test --filter FormSplitRequirementTests`
Expected: 컴파일 실패 — `formRequirementsRaw`·`formVariantKey`·`detailForTesting` 이 없고, `.item` 이 아직 `String` 하나를 받는다.

> `.item(["cracked-pot"])` 은 Task 4 에서 들어오는 모양이다. **Task 1 에서는 `.item("cracked-pot")`(단수) 로 쓰고**, Task 4 의 Step 5 에서 이 테스트의 기대값을 배열로 바꾼다. 순서를 뒤집지 마라 — enum 을 먼저 바꾸면 Task 1 의 실패가 "컴파일 안 됨"으로 뭉개져 트리거 브랜치를 안 밟는다.

- [ ] **Step 3: `EvoNode` 에 자리를 만든다**

`Sources/PokeDexBar/Core/CompanionModel.swift`, `regionalRequirementRaw` 바로 아래:

```swift
    /// **태생 모습일 때의** 조건 — 그 모습에만 걸리는 요구가 있을 때만 채워진다(2종: 데인차·차데스).
    ///
    /// 지방(`regionalRequirementRaw`)과 같은 모양이지만 축이 다르다. 데인차는 위작이면 깨진포트,
    /// 진작이면 이빠진포트로 포트데스가 된다 — 하나로 접으면 진작이 깨진포트를 요구한다(실측).
    /// 키는 `BirthFormCatalog` 의 변종 키(`"antique"`·`"artisan"`)다.
    var formRequirementsRaw: [String: EvoRequirementRaw] = [:]

    /// 이 태생 모습의 조건. 그 모습 전용 조건이 없으면 기본 조건을 쓴다.
    func requirement(forFixedForm variant: String?) -> EvoRequirement {
        guard let variant, let raw = formRequirementsRaw[variant] else { return requirement }
        return Self.resolve(raw)
    }
```

- [ ] **Step 4: 변종 키 추출과 분류를 파서에 넣는다**

`Sources/PokeDexBar/Core/PokeAPIClient.swift`, `isRegional` 아래:

```swift
    /// 이 조건줄이 **부모의 어느 태생 모습** 것인가. 모습과 무관하면 nil.
    ///
    /// **첫 하이픈으로 자르지 않는다** — 종 이름 자체에 하이픈이 있다(`mr-mime`·`jangmo-o`).
    /// 부모 종이 실제로 가진 변종 키와 **접미사로 대조**한다. 그래서 이브이의 `eevee-starter`
    /// 처럼 태생 모습이 아닌 값은 저절로 걸러진다 — 값의 유무로 가르면 이브이가 조건을 잃는다.
    static func formVariantKey(_ detail: EvolutionDetail, parentSpeciesID: Int) -> String? {
        guard let name = detail.required_pokemon_form?.name else { return nil }
        return BirthFormCatalog.forms(speciesID: parentSpeciesID)
            .map(\.variant)
            .first { name.hasSuffix("-\($0)") }
    }

    #if DEBUG
    /// 변종 키 추출만 따로 보기 위한 테스트 헬퍼.
    static func detailForTesting(requiredForm: String) -> EvolutionDetail {
        let json = #"{"required_pokemon_form":{"name":"\#(requiredForm)"}}"#
        return try! JSONDecoder().decode(EvolutionDetail.self, from: Data(json.utf8))
    }
    #endif

    /// 태생 모습 전용 조건들. 기본형 줄은 여기 안 들어간다(`requirement` 가 가져간다).
    static func formRequirements(from details: [EvolutionDetail]?,
                                 parentSpeciesID: Int,
                                 speciesID: Int, parentLevel: Int) -> [String: EvoRequirementRaw] {
        guard let details else { return [:] }
        var out: [String: EvoRequirementRaw] = [:]
        for detail in details {
            guard let key = Self.formVariantKey(detail, parentSpeciesID: parentSpeciesID) else { continue }
            out[key] = Self.requirement(from: [detail], speciesID: speciesID, parentLevel: parentLevel)
        }
        return out
    }
```

`requirement(from:speciesID:parentLevel:)` 안의 `own` 필터에 한 줄을 더한다 — 모습 전용 줄도 기본 조건에서 빼야 한다. `let own = all.filter { !Self.isRegional($0) }` 를 다음으로 바꾼다:

```swift
        // 지방 줄도, 태생 모습 전용 줄도 **원종/기본형의 조건이 아니다.** 안 갈라내면 진작의
        // 이빠진포트가 위작의 깨진포트를 가로챈다(실측: 두 줄 중 먼저 온 쪽이 이겼다).
        let own = all.filter { !Self.isRegional($0) && !Self.isFormSpecific($0, parentSpeciesID: parentSpeciesID) }
```

그리고 `requirement` 의 시그니처에 `parentSpeciesID: Int` 를 더하고, 아래 헬퍼를 둔다:

```swift
    static func isFormSpecific(_ detail: EvolutionDetail, parentSpeciesID: Int) -> Bool {
        Self.formVariantKey(detail, parentSpeciesID: parentSpeciesID) != nil
    }
```

- [ ] **Step 5: `node(from:)` 이 부모 종을 넘긴다**

`Sources/PokeDexBar/Core/PokeAPIClient.swift:315`:

```swift
    static func node(from link: ChainLink, parentLevel: Int = 1, parentSpeciesID: Int = 0) -> EvoNode {
        let speciesID = Self.id(from: link.species.url ?? "")
        let raw = Self.requirement(from: link.evolution_details, parentSpeciesID: parentSpeciesID,
                                   speciesID: speciesID, parentLevel: parentLevel)
        let myLevel = if case .level(let n) = raw { n } else { parentLevel }
        let real = link.evolves_to.filter { !($0.evolution_details?.isEmpty ?? true) }
        return EvoNode(speciesID: speciesID,
                       children: real.map { node(from: $0, parentLevel: myLevel,
                                                 parentSpeciesID: speciesID) },
                       requirementRaw: raw,
                       regionalRequirementRaw: Self.regionalRequirement(from: link.evolution_details),
                       formRequirementsRaw: Self.formRequirements(
                           from: link.evolution_details, parentSpeciesID: parentSpeciesID,
                           speciesID: speciesID, parentLevel: parentLevel),
                       requiredGender: Self.gender(from: link.evolution_details))
    }
```

`EvoNode` 의 멤버 순서에 맞춰 이니셜라이저 인자 순서를 맞춘다(구조체 합성 이니셜라이저라 선언 순서를 따른다).

- [ ] **Step 6: 테스트가 통과하는지 확인한다**

Run: `swift test --filter "FormSplitRequirementTests|EvoRequirementParsingTests|FabricatedChainEdgeTests|RegionTests"`
Expected: PASS. 지방·피오네 가드가 함께 통과해야 한다 — `own` 필터를 건드렸기 때문이다.

- [ ] **Step 7: 전체 테스트**

Run: `swift test`
Expected: 1617개 통과(9 skip), 0 실패.

- [ ] **Step 8: 커밋**

```bash
git add Sources/PokeDexBar/Core/CompanionModel.swift Sources/PokeDexBar/Core/PokeAPIClient.swift Tests/PokeDexBarTests/EvolutionItemTests.swift
git commit -m "fix: split evolution conditions that differ per birth form

Sinistea and Poltchageist carry two condition lines each, told apart by
required_pokemon_form, and folding them into one made the rare variant
demand the common form's item. Parse the variant-specific lines into their
own map, matching the parent's known variant keys by suffix so hyphenated
species names and unrelated form names (Eevee's nineteen lines) fall
through to the base condition."
```

---

### Task 2: 조회가 태생 모습을 본다

**Files:**
- Modify: `Sources/PokeDexBar/Player/PlayerStore+Evolution.swift:133-137` (`requirement(for:line:region:)`)
- Modify: `Sources/PokeDexBar/UI/IndividualDetailView.swift:490`, `:527`, `:547`, `:564`
- Test: `Tests/PokeDexBarTests/EvolutionItemTests.swift` (`FormSplitRequirementTests` 에 추가)

**Interfaces:**
- Consumes: `EvoNode.requirement(forFixedForm:)` (Task 1)
- Produces: `PlayerStore.requirement(for:line:region:fixedForm:) -> EvoRequirement`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`FormSplitRequirementTests` 에 추가:

```swift
    private func sinisteaLine() -> EvoLine {
        let dto = try! JSONDecoder().decode(ChainDTO.self, from: Data(sinisteaChain.utf8))
        return EvoLine(baseID: 854, tree: PokeAPIClient.node(from: dto.chain),
                       rarity: .common, names: [:])
    }

    private func store() -> PlayerStore {
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
```

- [ ] **Step 2: 실패를 확인한다**

Run: `swift test --filter FormSplitRequirementTests`
Expected: 컴파일 실패 — `requirement(for:line:region:fixedForm:)` 가 없다.

- [ ] **Step 3: 조회 축을 더한다**

`Sources/PokeDexBar/Player/PlayerStore+Evolution.swift`:

```swift
    /// 이 갈래를 지나려면 무엇이 필요한가. 트리에 없는 종이면 조건 없음으로 본다.
    ///
    /// **축이 둘이다.** 지방(모래사원 계열 4종)과 태생 모습(데인차·차데스). 우선순위는
    /// 태생 모습 → 지방 → 기본이다 — 둘 다 걸리는 종은 없지만, 순서를 정해 두지 않으면
    /// 나중에 생길 때 조용히 한쪽이 먹힌다.
    func requirement(for speciesID: Int, line: EvoLine, region: Region?,
                     fixedForm: String? = nil) -> EvoRequirement {
        guard let node = line.tree.node(withID: speciesID) else { return .none }
        if let fixedForm, node.formRequirementsRaw[fixedForm] != nil {
            return node.requirement(forFixedForm: fixedForm)
        }
        return region == nil ? node.requirement : node.regionalRequirement
    }
```

- [ ] **Step 4: 호출부 다섯 곳이 개체의 변종을 넘긴다**

`canEvolve`(`PlayerStore+Evolution.swift:157`):

```swift
            && meetsRequirement(requirement(for: speciesID, line: line, region: individual.region,
                                            fixedForm: individual.birthForm),
                                for: individual)
```

> **이 시점에는 아직 `birthForm` 이다.** 개명은 Task 5 다. Task 2 에서는 `individual.birthForm` 으로 쓰고, Task 5 의 개명 단계에서 한꺼번에 바뀐다.

`IndividualDetailView.swift` 네 곳(`:490`·`:527`·`:547`·`:564`)에 같은 방식으로 `fixedForm:` 인자를 더한다. `:547` 의 `blockedSummary` 는 `region` 만 받고 있으므로 `fixedForm: String? = nil` 파라미터를 함께 더하고, 호출부(`:527` 근처)가 `individual.birthForm` 을 넘긴다.

- [ ] **Step 5: 테스트 통과 확인**

Run: `swift test --filter "FormSplitRequirementTests|EvolutionBranchFoldingTests"`
Expected: PASS.

- [ ] **Step 6: 전체 테스트**

Run: `swift test`
Expected: 0 실패.

- [ ] **Step 7: 커밋**

```bash
git add Sources/PokeDexBar/Player/PlayerStore+Evolution.swift Sources/PokeDexBar/UI/IndividualDetailView.swift Tests/PokeDexBarTests/EvolutionItemTests.swift
git commit -m "fix: pick the evolution condition by the individual's birth form

An antique Sinistea now asks for the Chipped Pot and a phony one for the
Cracked Pot. Saves written before birth forms existed carry nil and fall
through to the base condition, which is the common form."
```

---

### Task 3: 채집이 태생 모습을 따른다

**Files:**
- Modify: `Sources/PokeDexBar/Player/ForageCatalog.swift:15-40` (`RegionScope`·`Need`), `:42-171` (표), `:169-171` (`needs`)
- Modify: `Sources/PokeDexBar/Player/PlayerStore+Forms.swift:89` (`forageTargets`)
- Test: `Tests/PokeDexBarTests/EvolutionItemTests.swift`

**Interfaces:**
- Produces: `ForageCatalog.FormScope`, `ForageCatalog.Need.formScope`, `ForageCatalog.needs(speciesID:region:fixedForm:) -> [EvolutionItem]`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```swift
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
```

- [ ] **Step 2: 실패를 확인한다**

Run: `swift test --filter FormScopedForageTests`
Expected: 컴파일 실패 — `needs` 에 `fixedForm` 인자가 없다.

- [ ] **Step 3: `FormScope` 를 더한다**

`Sources/PokeDexBar/Player/ForageCatalog.swift`, `RegionScope` 아래:

```swift
    /// 이 갈래가 어느 **태생 모습** 개체에게 해당하는가. `RegionScope` 와 같은 모양이고 축만
    /// 다르다 — 지방은 "어디서 왔나", 이건 "그렇게 태어났나"다. 데인차·차데스 둘뿐이다.
    enum FormScope: Sendable, Equatable, Hashable {
        case any
        /// 그 태생 모습만. `nil` 은 기본형(위작 데인차·범작 차데스).
        case only(String?)

        func covers(_ fixedForm: String?) -> Bool {
            switch self {
            case .any: true
            case .only(let v): v == fixedForm
            }
        }
    }
```

`Need` 에 필드를 더한다(기본값 `.any` 라 기존 90여 항목은 안 고쳐도 된다):

```swift
    struct Need: Sendable, Equatable, Hashable {
        let to: Int
        let item: EvolutionItem
        let scope: RegionScope
        var formScope: FormScope = .any
    }
```

`needs` 를 바꾼다:

```swift
    static func needs(speciesID: Int, region: Region?, fixedForm: String? = nil) -> [EvolutionItem] {
        (bySpecies[speciesID] ?? [])
            .filter { $0.scope.covers(region) && $0.formScope.covers(fixedForm) }
            .map(\.item)
    }
```

- [ ] **Step 4: 두 종의 표를 가른다**

`Sources/PokeDexBar/Player/ForageCatalog.swift` 의 854·1012 항목:

```swift
        854: [
            .init(to: 855, item: .crackedPot, scope: .any, formScope: .only(nil)),
            .init(to: 855, item: .chippedPot, scope: .any, formScope: .only("antique")),
        ],
```
```swift
        1012: [
            .init(to: 1013, item: .unremarkableTeacup, scope: .any, formScope: .only(nil)),
            .init(to: 1013, item: .masterpieceTeacup, scope: .any, formScope: .only("artisan")),
        ],
```

- [ ] **Step 5: `forageTargets` 가 개체의 변종을 넘긴다**

`Sources/PokeDexBar/Player/PlayerStore+Forms.swift:89`:

```swift
        let evolution = ForageCatalog.needs(speciesID: individual.speciesID,
                                            region: individual.region,
                                            fixedForm: individual.birthForm)
```

- [ ] **Step 6: 테스트 통과 확인**

Run: `swift test --filter "FormScopedForageTests|EvolutionItemCatalogTests"`
Expected: PASS. **`testEveryItemIsObtainableByForaging` 가 특히 중요하다** — 모습으로 가르면서 어떤 도구가 아무에게도 안 물어와지면 거기서 깨진다.

- [ ] **Step 7: 전체 테스트 후 커밋**

Run: `swift test` → 0 실패.

```bash
git add Sources/PokeDexBar/Player/ForageCatalog.swift Sources/PokeDexBar/Player/PlayerStore+Forms.swift Tests/PokeDexBarTests/EvolutionItemTests.swift
git commit -m "fix: forage only the pot the individual's form can use

A phony Sinistea was spending days fetching a Chipped Pot it can never
use, and an antique one the Cracked Pot. Scope those two entries by birth
form the way regional entries are scoped by region."
```

---

### Task 4: 진화 조건이 도구 **집합**을 든다

**Files:**
- Modify: `Sources/PokeDexBar/Core/CompanionModel.swift:58-68` (`EvoRequirementRaw`), `:95-105` (`resolve`)
- Modify: `Sources/PokeDexBar/Player/EvolutionItem.swift:121-131` (`EvoRequirement`)
- Modify: `Sources/PokeDexBar/Core/PokeAPIClient.swift` (`requirement`·`regionalRequirement`)
- Modify: `Sources/PokeDexBar/Player/PlayerStore+Evolution.swift` (`meetsRequirement`)
- Modify: `Sources/PokeDexBar/UI/IndividualDetailView.swift` (`shortNeed`·`blockedHints`)
- Test: `Tests/PokeDexBarTests/EvolutionItemTests.swift`

**Interfaces:**
- Produces: `EvoRequirement.item([EvolutionItem])`, `EvoRequirementRaw.item([String])`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```swift
/// 원작에서 **도구 두 개가 모두 유효한** 갈래가 있다 — 치고마의 족자 둘은 각각 다른 우라오스가
/// 된다. 조건을 도구 하나로 들면 뒤의 하나가 영영 쓸 데가 없다(실측: 물의족자가 그랬다).
final class ItemSetRequirementTests: XCTestCase {
    /// `evolution-chain/470` 에서 잘라 왔다.
    private let kubfuChain = """
    {"chain": {
      "species": {"name": "kubfu", "url": "https://pokeapi.co/api/v2/pokemon-species/891/"},
      "evolution_details": [],
      "evolves_to": [{
        "species": {"name": "urshifu", "url": "https://pokeapi.co/api/v2/pokemon-species/892/"},
        "evolution_details": [
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

    /// **아는 도구가 하나도 없으면 집합을 만들지 않는다.** `.item([])` 은 `.none` 으로 풀려
    /// 조건 없이 진화시킨다 — 마빌크가 레벨 폴백으로 떨어져야 하는 이유와 같은 자리다.
    func testUnknownItemsDoNotMakeAnEmptySet() {
        let need = PokeAPIClient.requirement(
            from: [PokeAPIClient.detailForTesting(item: "rare-candy")],
            parentSpeciesID: 0, speciesID: 4, parentLevel: 1)
        XCTAssertNotEqual(need, .item([]))
        XCTAssertEqual(need, .level(20), "조건 없음으로 떨어졌다 — 공짜 진화가 된다")
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
}
```

`detailForTesting` 에 `item:` 변형을 더한다(Task 1 의 헬퍼 확장):

```swift
    #if DEBUG
    static func detailForTesting(item: String? = nil, requiredForm: String? = nil) -> EvolutionDetail {
        var fields: [String] = []
        if let item { fields.append(#""item":{"name":"\#(item)"}"#) }
        if let requiredForm { fields.append(#""required_pokemon_form":{"name":"\#(requiredForm)"}"#) }
        let json = "{\(fields.joined(separator: ","))}"
        return try! JSONDecoder().decode(EvolutionDetail.self, from: Data(json.utf8))
    }
    #endif
```

- [ ] **Step 2: 실패를 확인한다**

Run: `swift test --filter ItemSetRequirementTests`
Expected: 컴파일 실패 — `.item` 이 아직 단수다.

- [ ] **Step 3: enum 둘을 집합으로 바꾼다**

`CompanionModel.swift`:

```swift
    /// 이 도구들 **중 하나**가 필요하다. 대부분 하나지만 둘인 갈래가 있다(치고마의 족자 둘,
    /// 마빌크의 사탕공예 일곱). 하나/여럿을 케이스로 가르지 않는 이유: 그건 데이터의 우연이지
    /// 의미 차이가 아니라, 가르면 모든 `switch` 가 도구 모양 분기를 둘씩 영구히 갖는다.
    case item([String])
```

`resolve`:

```swift
        case .item(let names):
            let items = names.compactMap(EvolutionItem.named)
            return items.isEmpty ? .none : .item(items)
```

`EvolutionItem.swift` 의 `EvoRequirement`:

```swift
    /// 이 도구들 중 **하나**를 써야 한다(돌·연결의 끈·특수 도구).
    case item([EvolutionItem])
```

- [ ] **Step 4: 파서가 집합을 모은다**

`PokeAPIClient.requirement` 의 도구 루프를 **첫 일치에서 반환하지 않고 모으도록** 바꾼다:

```swift
        var items: [String] = []
        var sawTrade = false
        for d in details {
            if let item = d.item?.name, EvolutionItem.named(item) != nil, !items.contains(item) {
                items.append(item)
            }
            if d.trigger?.name == "trade" {
                sawTrade = true
                if let held = d.held_item?.name, EvolutionItem.named(held) != nil,
                   !items.contains(held) { items.append(held) }
            } else if let held = d.held_item?.name, EvolutionItem.named(held) != nil,
                      !items.contains(held) {
                items.append(held)
            }
        }
        if !items.isEmpty { return .item(items) }
        // 교환인데 들 물건을 못 알아봤으면 연결의 끈으로 대신한다 — 이 앱엔 교환 상대가 없다.
        if sawTrade { return .item([EvolutionItem.linkingCord.rawValue]) }
```

`regionalRequirement` 도 같은 방식으로 모은다(지방 줄끼리만).

- [ ] **Step 5: 나머지 `switch` 네 곳을 맞춘다**

- `PlayerStore+Evolution.meetsRequirement`: `case .item(let items): items.contains { count(of: $0) > 0 }`
- `IndividualDetailView.shortNeed`: `case .item(let items):` → 2개 이하면 `items.map { $0.label(l.lang) }.joined(separator: " / ")`, 3개 이상이면 `l.evolveNeedsOneOf(items[0].label(l.lang), items.count)`
- `IndividualDetailView.blockedHints`: `if case .item = $0` 은 그대로 동작한다(연관값 무시).
- `Localization.swift` 에 문구를 더한다:

```swift
    /// 도구가 셋 이상인 갈래의 접힌 줄 — 이름을 다 늘어놓으면 한 줄을 넘는다(마빌크는 일곱이다).
    func evolveNeedsOneOf(_ first: String, _ count: Int) -> String {
        t("\(first) 등 \(count)종", "\(first) or \(count - 1) more", "\(first)など\(count)種")
    }
```

Task 1 의 테스트 기대값을 배열로 고친다: `.item("cracked-pot")` → `.item(["cracked-pot"])`, `.item("chipped-pot")` → `.item(["chipped-pot"])`, `.item("water-stone")` → `.item(["water-stone"])`.

- [ ] **Step 6: 테스트 통과 확인**

Run: `swift test --filter "ItemSetRequirementTests|FormSplitRequirementTests|EvoRequirementParsingTests|EvolutionBranchFoldingTests|CopyStyleTests"`
Expected: PASS. `KoreanToneTests` 가 새 문구를 잡으므로 해요체·조사 규칙을 지켜야 한다.

- [ ] **Step 7: 전체 테스트 후 커밋**

Run: `swift test` → 0 실패.

```bash
git add Sources/PokeDexBar/Core/CompanionModel.swift Sources/PokeDexBar/Core/PokeAPIClient.swift Sources/PokeDexBar/Player/EvolutionItem.swift Sources/PokeDexBar/Player/PlayerStore+Evolution.swift Sources/PokeDexBar/UI/IndividualDetailView.swift Sources/PokeDexBar/Core/Localization.swift Tests/PokeDexBarTests/EvolutionItemTests.swift
git commit -m "feat: let an evolution accept any one of several items

Kubfu takes either scroll and Milcery takes any sweet, but the condition
held a single item, so the second scroll was inert. Carry the whole set
and satisfy it with any member. An empty set would resolve to no condition
at all, so a branch whose items are all unknown keeps falling back to a
level instead."
```

---

### Task 5: 고정 변종 저장소를 합치고, 쓴 도구를 기록한다

**Files:**
- Modify: `Sources/PokeDexBar/Player/Individual.swift:101` (`birthForm` → `fixedForm`), `:120-127`, `:177-180`, `:308`
- Create: `Sources/PokeDexBar/Player/EvolvedFormCatalog.swift`
- Create: `Sources/PokeDexBar/Player/FixedForm.swift`
- Modify: `Sources/PokeDexBar/Player/DexKey.swift:32-35`
- Modify: `Sources/PokeDexBar/Player/PlayerStore+Evolution.swift` (`evolve`)
- Test: `Tests/PokeDexBarTests/EvolutionItemTests.swift`

**Interfaces:**
- Produces: `Individual.fixedForm: String?`(저장 키는 `birthForm`), `FixedForm.resolve(speciesID:variant:) -> (slug: String, label: FormLabel)?`, `EvolvedFormCatalog.variant(speciesID:item:) -> String?`, `PlayerStore.evolve(individualID:to:line:using:)`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```swift
/// 진화할 때 쓴 도구가 결과의 모습을 정하고, 그 모습은 **평생 간다**(원작에서 되돌릴 방법이 없다).
final class EvolvedFormTests: XCTestCase {
    /// `evolution-chain/470` 에서 잘라 왔다(Task 4 와 같은 픽스처 — 파일이 달라 다시 적는다).
    private let kubfuChain = """
    {"chain": {
      "species": {"name": "kubfu", "url": "https://pokeapi.co/api/v2/pokemon-species/891/"},
      "evolution_details": [],
      "evolves_to": [{
        "species": {"name": "urshifu", "url": "https://pokeapi.co/api/v2/pokemon-species/892/"},
        "evolution_details": [
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

    /// **도감 키는 변종을 박은 뒤에 등록돼야 한다.** 먼저 등록하면 연격이 일격 칸에 들어간다.
    @MainActor func testTheDexRecordsTheResultingForm() {
        let (store, line) = kubfuStore()
        store.grantForTesting(EvolutionItem.scrollOfWaters)
        store.evolve(individualID: store.state.box[0].id, to: 892, line: line, using: .scrollOfWaters)
        XCTAssertTrue(store.state.dexForms.contains(DexKey.key(for: store.state.box[0])))
        XCTAssertFalse(store.state.dexForms.contains("892"), "일격 칸이 같이 켜졌다")
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

    /// 두 카탈로그가 같은 종에서 변종 키를 두고 다투면 안 된다.
    func testTheTwoCatalogsDoNotOverlap() {
        for (speciesID, variants) in EvolvedFormCatalog.variantsBySpecies {
            let birth = Set(BirthFormCatalog.forms(speciesID: speciesID).map(\.variant))
            XCTAssertTrue(birth.isDisjoint(with: Set(variants)),
                          "#\(speciesID) 의 변종 키가 겹친다")
        }
    }
}
```

- [ ] **Step 2: 실패를 확인한다**

Run: `swift test --filter EvolvedFormTests`
Expected: 컴파일 실패.

- [ ] **Step 3: `birthForm` 을 `fixedForm` 으로 개명한다(저장 키 유지)**

`Individual.swift:101`:

```swift
    /// **정해지면 평생 안 바뀌는 변종 키.** 대개 부화 때 정해지고(`BirthFormCatalog` — 안농의
    /// 글자, 비비용의 무늬, 데인차의 진작), 둘은 **진화할 때** 정해진다(`EvolvedFormCatalog` —
    /// 쓴 족자가 우라오스의 태세를, 쓴 사탕공예가 마휘핑의 모습을 정한다).
    ///
    /// 지방(`region`)과 성격이 같다 — 도구로 안 바뀌고 진화해도 이어진다. 폼(`form`)과는
    /// 반대다: 폼은 되돌릴 수 있고 진화하면 풀린다.
    ///
    /// 슬러그가 아니라 키를 담는 이유는 단계마다 슬러그가 다르기 때문이다
    /// (`flabebe-blue` → `floette-blue` → `florges-blue`).
    ///
    /// **저장 키는 `birthForm` 그대로다** — 옛 세이브를 읽어야 한다.
    var fixedForm: String?
```

`CodingKeys` 와 `init(from:)`(`:308`)에서 키 문자열 `birthForm` 을 유지한다. 나머지 참조를 전부 바꾼다:

Run: `grep -rn "birthForm" Sources/ Tests/ | grep -v "BirthForm"` 로 확인하고 하나씩 고친다. `birthFormLabel` 은 **이름을 유지한다**(배지 이름이고 호출부가 여럿이다).

- [ ] **Step 4: `EvolvedFormCatalog` 를 만든다**

`Sources/PokeDexBar/Player/EvolvedFormCatalog.swift`:

```swift
import Foundation

/// **진화할 때 쓴 도구가 정하는 겉모습.** 부화 때 정해지는 `BirthFormCatalog` 와 성질이 같고
/// (키로 저장, 평생 고정, 되돌릴 수 없음) 정해지는 **시점만** 다르다. 그래서 저장도 같은 자리
/// (`Individual.fixedForm`)를 쓴다.
///
/// 전 540체인 전수 확인(2026-10-12): 도구가 결과 모습을 가르는 간선은 **둘뿐이다.**
///
/// **기본형 쪽은 키를 안 박는다** — "후보 없음이 곧 기본형"이라, 그래야 도감 키가
/// `892` / `892-urshifu-rapidstrike` 로 자연스럽게 갈린다.
///
/// ## 마휘핑은 의도된 어긋남이다
///
/// 원작에서 사탕공예는 **위에 올라가는 장식**을 정하고, 몸 색(크림 9종)은 회전 방향·시간이
/// 정한다. 둘은 완전히 독립이라 응답에 63조합이 전부 들어 있다. 그런데 Showdown 에는
/// **크림 기준 그림만** 있고 사탕공예 기준 그림이 없다(`alcremie-strawberrysweet` 404).
/// 메커니즘이 옮겨지는 축에는 그림이 없고 그림이 있는 축에는 메커니즘이 없어서, 사탕공예에
/// 크림을 붙였다. 사용자 결정이다 — "플레이어가 자기 마휘핑의 모습을 고른다"를 지키는 쪽.
/// **원작대로 되돌리려 하지 마라** — 장식 스프라이트가 없다는 벽에 다시 부딪힌다.
enum EvolvedFormCatalog {
    struct Decided: Sendable, Equatable {
        let speciesID: Int
        let item: EvolutionItem
        /// nil 이면 기본형 — 키를 안 박는다.
        let variant: String?
        /// 변종일 때의 Showdown 슬러그. 기본형이면 nil.
        let slug: String?
        let label: FormLabel?
    }

    static let all: [Decided] = [
        .init(speciesID: 892, item: .scrollOfDarkness, variant: nil, slug: nil, label: nil),
        .init(speciesID: 892, item: .scrollOfWaters, variant: "rapidstrike",
              slug: "urshifu-rapidstrike",
              label: .init("연격의 태세", "Rapid Strike Style", "れんげきのかた")),
    ]

    static func variant(speciesID: Int, item: EvolutionItem) -> String? {
        all.first { $0.speciesID == speciesID && $0.item == item }?.variant
    }

    static func form(speciesID: Int, variant: String) -> (slug: String, label: FormLabel)? {
        guard let hit = all.first(where: { $0.speciesID == speciesID && $0.variant == variant }),
              let slug = hit.slug, let label = hit.label else { return nil }
        return (slug, label)
    }

    /// 테스트가 두 카탈로그의 키 충돌을 보기 위한 색인.
    static var variantsBySpecies: [Int: [String]] {
        Dictionary(grouping: all.compactMap { d in d.variant.map { (d.speciesID, $0) } },
                   by: \.0).mapValues { $0.map(\.1) }
    }
}
```

- [ ] **Step 5: `FixedForm.resolve` 한 자리를 만들고 세 호출부를 옮긴다**

`Sources/PokeDexBar/Player/FixedForm.swift`:

```swift
import Foundation

/// 고정 변종 키 → 그 단계의 겉모습. **두 카탈로그를 여기서만 묻는다** — 그리는 자리
/// (`Individual.spriteForm`)·도감 키(`DexKey`)·배지(`birthFormLabel`) 셋이 각각 카탈로그를
/// 직접 부르면 카탈로그가 늘 때마다 분기가 셋씩 는다.
enum FixedForm {
    static func resolve(speciesID: Int, variant: String) -> (slug: String, label: FormLabel)? {
        if let born = BirthFormCatalog.form(speciesID: speciesID, variant: variant) {
            return (born.slug, born.label)
        }
        return EvolvedFormCatalog.form(speciesID: speciesID, variant: variant)
    }
}
```

`Individual.spriteForm`(`:177`)·`birthFormLabel`(`:124`)·`DexKey.key(for:)`(`:32`)의 `BirthFormCatalog.form(speciesID:variant:)` 호출을 `FixedForm.resolve(speciesID:variant:)` 로 바꾼다(반환이 튜플이라 `.slug`·`.label` 로 받는다).

- [ ] **Step 6: `evolve` 가 도구를 받아 변종을 박는다**

`PlayerStore+Evolution.swift`:

```swift
    /// 진화 실행. 갈 수 없는 종이거나 조건을 못 채웠으면 아무것도 하지 않고 false.
    ///
    /// **`using` 은 요구 도구가 여럿일 때 필수다.** 생략하면 호출부가 조용히 첫 번째를 쓰게 되어
    /// 플레이어의 선택이 사라진다(어떤 족자를 썼는지가 우라오스의 태세를 정한다).
    @discardableResult
    func evolve(individualID: UUID, to speciesID: Int, line: EvoLine,
                using chosen: EvolutionItem? = nil) -> Bool {
        guard let index = state.box.firstIndex(where: { $0.id == individualID }) else { return false }
        let individual = state.box[index]
        guard canEvolve(individual, to: speciesID, line: line) else { return false }
        let need = requirement(for: speciesID, line: line, region: individual.region,
                               fixedForm: individual.fixedForm)
        var used: EvolutionItem?
        if case .item(let items) = need {
            if let chosen {
                guard items.contains(chosen), count(of: chosen) > 0 else { return false }
                used = chosen
            } else {
                guard items.count == 1 else { return false }
                used = items[0]
            }
        } else if chosen != nil {
            return false   // 도구 조건이 아닌데 도구를 넘겼다 — 호출부가 뭔가 잘못 알고 있다.
        }
        ...
```

`mutate` 블록 안, **`dexForms.insert` 보다 먼저**:

```swift
            // **도감 키를 등록하기 전에 박아야 한다** — 뒤에 두면 연격 우라오스가 일격 칸에 들어간다.
            if let used, let variant = EvolvedFormCatalog.variant(speciesID: speciesID, item: used) {
                state.box[index].fixedForm = variant
            }
            state.dexForms.insert(DexKey.key(for: state.box[index]))
```

- [ ] **Step 7: 테스트 통과 확인**

Run: `swift test --filter "EvolvedFormTests|IndividualDecodeTests|PlayerStateTests|BirthFormTests|NationalDexTests"`
Expected: PASS.

**저장 키가 유지되는지 직접 잠근다.** 개명은 속성명만 바꾸는 것이고, 키까지 따라 바뀌면 옛
세이브의 안농 글자·비비용 무늬·데인차 진작이 통째로 날아간다. `IndividualDecodeTests` 에 추가:

```swift
    /// [회귀] `birthForm` → `fixedForm` 개명은 **속성명만**이다. 저장 키가 따라 바뀌면 옛
    /// 세이브의 변종이 전부 nil 이 되어 안농이 A 로, 진작 데인차가 위작으로 돌아간다.
    func testTheStoredKeyIsStillBirthForm() throws {
        let json = #"{"id":"\#(UUID().uuidString)","baseID":854,"speciesID":854,"pathIDs":[854],"#
            + #""nature":"serious","obtainedAt":0,"grade":"common","birthForm":"antique"}"#
        let decoded = try JSONDecoder().decode(Individual.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.fixedForm, "antique", "옛 세이브의 변종을 잃었다")
    }
```

필드 이름·형식은 같은 파일의 기존 디코드 테스트를 그대로 따른다(이 레포의 `Individual` 은
`init(from:)` 을 직접 구현하고 있어 키 누락에 관대하다 — 기존 테스트가 쓰는 최소 JSON 을 베낀다).

- [ ] **Step 8: 전체 테스트 후 커밋**

Run: `swift test` → 0 실패.

```bash
git add Sources/PokeDexBar/Player/ Sources/PokeDexBar/UI/ Tests/PokeDexBarTests/
git commit -m "feat: let the item used at evolution decide the resulting form

Kubfu becomes Single Strike or Rapid Strike Urshifu depending on the
scroll, which the app could not express. The decision lands in the field
that already holds permanent variants, renamed from birthForm to fixedForm
since it is no longer only set at hatching; the stored key is unchanged so
old saves still read. Both catalogs are now asked through one resolver.

The variant is written before the dex key is recorded. The other order
files Rapid Strike under the Single Strike slot."
```

---

### Task 6: 마휘핑 — 사탕공예 일곱과 크림 여섯

**Files:**
- Modify: `Sources/PokeDexBar/Player/EvolutionItem.swift` (사탕공예 7종)
- Modify: `Sources/PokeDexBar/Player/ForageCatalog.swift` (868 항목)
- Modify: `Sources/PokeDexBar/Player/UnstatedEvolutionCatalog.swift:46` (869 삭제)
- Modify: `Sources/PokeDexBar/Player/EvolvedFormCatalog.swift` (869 항목 7개)
- Modify: `Tests/PokeDexBarTests/Fixtures/ItemNames/official-item-names.json` (재생성)
- Test: `Tests/PokeDexBarTests/EvolutionItemTests.swift`

**Interfaces:**
- Consumes: `EvolvedFormCatalog.Decided`(Task 5), `ForageCatalog.Need`(Task 3)

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```swift
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
}
```

- [ ] **Step 2: 실패를 확인한다**

Run: `swift test --filter MilceryEvolutionTests`
Expected: 컴파일 실패 — `strawberrySweet` 등이 없다.

- [ ] **Step 3: 사탕공예 7종을 더한다**

`EvolutionItem.swift` 의 특수 도구 구역에:

```swift
    /// 마빌크의 사탕공예 일곱. 원작에서는 **위에 올라가는 장식**을 정하지만, 이 앱에서는 몸 색을
    /// 정한다 — 근거는 `EvolvedFormCatalog` 주석에 있다.
    case strawberrySweet = "strawberry-sweet"
    case berrySweet = "berry-sweet"
    case loveSweet = "love-sweet"
    case starSweet = "star-sweet"
    case cloverSweet = "clover-sweet"
    case flowerSweet = "flower-sweet"
    case ribbonSweet = "ribbon-sweet"
```

라벨은 **공식 이름이다**(PokéAPI 확인, 2026-10-14):

```swift
        case .strawberrySweet: ("딸기사탕공예", "Strawberry Sweet", "いちごアメざいく")
        case .berrySweet: ("베리사탕공예", "Berry Sweet", "ベリーアメざいく")
        case .loveSweet: ("하트사탕공예", "Love Sweet", "ハートアメざいく")
        case .starSweet: ("스타사탕공예", "Star Sweet", "スターアメざいく")
        case .cloverSweet: ("네잎사탕공예", "Clover Sweet", "よつばアメざいく")
        case .flowerSweet: ("꽃사탕공예", "Flower Sweet", "おはなアメざいく")
        case .ribbonSweet: ("리본사탕공예", "Ribbon Sweet", "リボンアメざいく")
```

- [ ] **Step 4: 카탈로그 셋을 고친다**

`ForageCatalog.bySpecies` 에:

```swift
        868: [
            .init(to: 869, item: .strawberrySweet, scope: .any),
            .init(to: 869, item: .berrySweet, scope: .any),
            .init(to: 869, item: .loveSweet, scope: .any),
            .init(to: 869, item: .starSweet, scope: .any),
            .init(to: 869, item: .cloverSweet, scope: .any),
            .init(to: 869, item: .flowerSweet, scope: .any),
            .init(to: 869, item: .ribbonSweet, scope: .any),
        ],
```

`UnstatedEvolutionCatalog.table` 에서 `869: .level(20),` 줄을 **지운다**(주석도 함께).

`EvolvedFormCatalog.all` 에 7줄을 더한다. 슬러그는 전부 200 확인(2026-10-12):

```swift
        .init(speciesID: 869, item: .strawberrySweet, variant: nil, slug: nil, label: nil),
        .init(speciesID: 869, item: .berrySweet, variant: "rubycream",
              slug: "alcremie-rubycream", label: .init("루비크림", "Ruby Cream", "ルビーミルク")),
        .init(speciesID: 869, item: .loveSweet, variant: "matchacream",
              slug: "alcremie-matchacream", label: .init("말차크림", "Matcha Cream", "マッチャミルク")),
        .init(speciesID: 869, item: .starSweet, variant: "mintcream",
              slug: "alcremie-mintcream", label: .init("민트크림", "Mint Cream", "ミントミルク")),
        .init(speciesID: 869, item: .cloverSweet, variant: "lemoncream",
              slug: "alcremie-lemoncream", label: .init("레몬크림", "Lemon Cream", "レモンミルク")),
        .init(speciesID: 869, item: .flowerSweet, variant: "saltedcream",
              slug: "alcremie-saltedcream", label: .init("솔트크림", "Salted Cream", "ソルトミルク")),
        .init(speciesID: 869, item: .ribbonSweet, variant: "rainbowswirl",
              slug: "alcremie-rainbowswirl",
              label: .init("레인보우스월", "Rainbow Swirl", "レインボーミックス")),
```

> **라벨을 손으로 적지 마라.** Task 8 이 `pokemon-form` 의 공식 이름으로 이 표를 잠근다 — 위 값은 그때 대조되고, 어긋나면 테스트가 깨진다.

- [ ] **Step 5: 아이템 이름 픽스처를 다시 만든다**

Run: `python3 scripts/generate-item-names.py`
Expected: `108 items (+8 invented)` — 사탕공예 7종이 늘어난다.

- [ ] **Step 6: 테스트 통과 확인**

Run: `swift test --filter "MilceryEvolutionTests|ItemNameTests|EvolutionItemCatalogTests|SpeciesSlugTests"`
Expected: PASS. `testEveryItemIsObtainableByForaging` 와 `testCatalogAndEnumAgreeOnTheItemSet` 이 새 7종을 함께 확인한다.

- [ ] **Step 7: 전체 테스트 후 커밋**

Run: `swift test` → 0 실패.

```bash
git add Sources/PokeDexBar/Player/ Tests/PokeDexBarTests/
git commit -m "feat: evolve Milcery with a sweet and let it decide the look

Milcery evolved at level 20 with no item at all, because the sweets are
held items under a spin trigger and none of them existed here. Add all
seven, forage all seven, and drop the level fallback that is now
unreachable.

Which cream each sweet opens is invented. In the games the sweet is the
decoration and the cream comes from how you spin, but Showdown draws only
the creams, so the choice had to land on the axis that has sprites."
```

---

### Task 7: 가진 도구마다 진화 버튼

**Files:**
- Modify: `Sources/PokeDexBar/UI/IndividualDetailView.swift:488-500` (`evolutionSection`)
- Modify: `Sources/PokeDexBar/Core/Localization.swift`
- Test: `Tests/PokeDexBarTests/FormTests.swift` (`EvolutionBranchFoldingTests` 에 추가)

**Interfaces:**
- Consumes: `PlayerStore.evolve(individualID:to:line:using:)`(Task 5)
- Produces: `IndividualDetailView.evolveChoices(_ target: Int, line: EvoLine, individual: Individual, store: PlayerStore) -> [EvolutionItem]`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```swift
    /// `evolution-chain/470` 에서 잘라 왔다(다른 파일이라 다시 적는다).
    private let kubfuChain = """
    {"chain": {
      "species": {"name": "kubfu", "url": "https://pokeapi.co/api/v2/pokemon-species/891/"},
      "evolution_details": [],
      "evolves_to": [{
        "species": {"name": "urshifu", "url": "https://pokeapi.co/api/v2/pokemon-species/892/"},
        "evolution_details": [
          {"trigger": {"name": "use-item"}, "item": {"name": "scroll-of-darkness"}},
          {"trigger": {"name": "use-item"}, "item": {"name": "scroll-of-waters"}}],
        "evolves_to": []}]}}
    """

    @MainActor private func kubfuStoreForUI() -> (PlayerStore, EvoLine) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("kubfu-ui-\(UUID().uuidString).json")
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

    /// 도구가 결과를 가르는 갈래는 **가진 도구마다** 버튼이 갈려야 한다 — 하나로 내면 어느
    /// 우라오스가 될지 플레이어가 못 고른다.
    @MainActor func testEachOwnedItemGetsItsOwnButton() {
        let (store, line) = kubfuStoreForUI()
        store.grantForTesting(EvolutionItem.scrollOfWaters)
        XCTAssertEqual(IndividualDetailView.evolveChoices(892, line: line,
                                                          individual: store.state.box[0],
                                                          store: store), [.scrollOfWaters])
        store.grantForTesting(EvolutionItem.scrollOfDarkness)
        XCTAssertEqual(Set(IndividualDetailView.evolveChoices(892, line: line,
                                                              individual: store.state.box[0],
                                                              store: store)),
                       [.scrollOfDarkness, .scrollOfWaters])
    }

    /// 결과가 안 갈리는 갈래는 버튼이 하나다 — 물의돌 이브이에 "물의돌로 진화"가 두 번 뜨면 안 된다.
    @MainActor func testBranchesThatDoNotSplitKeepOneButton() {
        let (store, _) = makeEevee()
        XCTAssertTrue(IndividualDetailView.evolveChoices(134, line: eeveeLine(),
                                                         individual: store.state.box[0],
                                                         store: store).count <= 1)
    }
```

- [ ] **Step 2: 실패를 확인한다**

Run: `swift test --filter EvolutionBranchFoldingTests`
Expected: 컴파일 실패 — `evolveChoices` 가 없다.

- [ ] **Step 3: 선택지 계산을 순수 함수로 만든다**

```swift
    /// 이 갈래를 **어떤 도구로** 지날 수 있나. 결과 모습이 도구마다 갈리는 종에서만 둘 이상이
    /// 나온다 — 안 갈리는 종은 버튼을 늘릴 이유가 없어 빈 배열(= 버튼 하나)로 둔다.
    @MainActor static func evolveChoices(_ target: Int, line: EvoLine, individual: Individual,
                                         store: PlayerStore) -> [EvolutionItem] {
        guard case .item(let items) = store.requirement(for: target, line: line,
                                                        region: individual.region,
                                                        fixedForm: individual.fixedForm)
        else { return [] }
        let owned = items.filter { store.count(of: $0) > 0 }
        let splits = Set(owned.map { EvolvedFormCatalog.variant(speciesID: target, item: $0) })
        return splits.count > 1 ? owned : []
    }
```

- [ ] **Step 4: `evolutionSection` 이 그 선택지를 버튼으로 낸다**

```swift
        ForEach(open, id: \.self) { target in
            let picks = Self.evolveChoices(target, line: line, individual: individual, store: store)
            if picks.isEmpty {
                DetailActionButton(title: choices.count > 1
                                   ? l.evolveTo(line.localizedName(target, store.language)) : l.evolve,
                                   prominent: true) {
                    store.evolve(individualID: individual.id, to: target, line: line)
                }
            } else {
                ForEach(picks, id: \.self) { item in
                    DetailActionButton(title: l.evolveWith(item.label(store.language)),
                                       prominent: true) {
                        store.evolve(individualID: individual.id, to: target, line: line, using: item)
                    }
                }
            }
        }
```

**`Josa` 에 로/으로가 없다**(이/가·을/를·은/는 뿐이다) — 먼저 더한다. `Sources/PokeDexBar/Core/Josa.swift`:

```swift
    /// 로/으로. **ㄹ받침은 "로" 다** — 받침 유무만 보면 "번개의돌으로"가 된다.
    static func roEuro(_ word: String) -> String {
        guard let last = word.unicodeScalars.last else { return "로" }
        if (0xAC00...0xD7A3).contains(last.value) {
            let final = (last.value - 0xAC00) % 28
            return (final == 0 || final == 8) ? "로" : "으로"   // 8 = ㄹ
        }
        return hasFinalConsonant(word) ? "으로" : "로"
    }
```

테스트(`Tests/PokeDexBarTests/CopyStyleTests.swift` 의 조사 테스트 옆):

```swift
    /// ㄹ받침은 "로" 다 — 받침 유무만 보면 "번개의돌으로"가 된다.
    func testTheRoParticleTreatsRieulAsNoFinalConsonant() {
        XCTAssertEqual(Josa.roEuro("천둥의돌"), "로")       // ㄹ
        XCTAssertEqual(Josa.roEuro("연결의끈"), "으로")     // ㄴ
        XCTAssertEqual(Josa.roEuro("딸기사탕공예"), "로")   // 받침 없음
    }
```

`Localization.swift`:

```swift
    /// 도구가 결과 모습을 가르는 갈래의 버튼 — 무엇을 쓰는지가 곧 어떤 모습이 되는지다.
    func evolveWith(_ item: String) -> String {
        t("\(item)\(Josa.roEuro(item)) 진화", "Evolve with \(item)", "\(item)でしんか")
    }
```

> 조사를 문구에 박지 않는다(`CopyStyleTests.testNoHardcodedJosaAnywhere`) — `discoveryFoundBy` 가 `Josa.iGa` 를 쓰는 것과 같은 방식이다.

- [ ] **Step 5: 테스트 통과 확인**

Run: `swift test --filter "EvolutionBranchFoldingTests|CopyStyleTests"`
Expected: PASS.

- [ ] **Step 6: 상세 화면 높이 회귀 확인**

Run: `swift test --filter testTheMostBranchedSpeciesStaysManageable`
Expected: PASS — 이브이 상세가 500pt 미만. 버튼이 늘어나는 것은 치고마·마빌크뿐이라 이브이는 안 바뀌어야 한다.

- [ ] **Step 7: 전체 테스트 후 커밋**

```bash
git add Sources/PokeDexBar/UI/IndividualDetailView.swift Sources/PokeDexBar/Core/Localization.swift Tests/PokeDexBarTests/FormTests.swift
git commit -m "feat: offer one evolve button per item that changes the outcome

Owning both scrolls now shows both, since which one you use is the whole
choice. Branches where the item does not change the result keep the single
button they had."
```

---

### Task 8: 부류 가드와 공식 폼 이름

**Files:**
- Modify: `scripts/generate-item-names.py` (폼 이름 추가)
- Create: `scripts/generate-evolution-form-edges.py`
- Create: `Tests/PokeDexBarTests/Fixtures/EvolutionForms/form-split-edges.json`
- Modify: `Package.swift` (resources)
- Create: `Tests/PokeDexBarTests/EvolutionFormCoverageTests.swift`

**Interfaces:**
- Consumes: `EvolvedFormCatalog.all`, `BirthFormCatalog.forms(speciesID:)`

- [ ] **Step 1: 간선 전수를 뽑는 스크립트를 쓴다**

`scripts/generate-evolution-form-edges.py` — PokéAPI 540체인을 받아 두 집합을 적는다:

```python
#!/usr/bin/env python3
"""진화 조건·결과가 갈리는 간선의 전수 목록 → 테스트 픽스처.

두 부류를 센다. ① 쓴 도구가 `evolved_pokemon_form` 을 가르는 간선 ② `required_pokemon_form`
으로 조건이 갈리는 간선. 카탈로그가 이 목록을 다 덮는지 `EvolutionFormCoverageTests` 가 본다.

**0 이 아닌 것을 확인하고 쓴다** — 한 번도 참이 안 되는 가드는 방어가 아니라 장식이다(CLAUDE.md).
"""
```

```python
import json
from concurrent.futures import ThreadPoolExecutor
# fetch() 는 generate-item-names.py 와 같다 — User-Agent 를 꼭 넣는다(urllib 기본값은 403).

OUT = "Tests/PokeDexBarTests/Fixtures/EvolutionForms/form-split-edges.json"

def species_id(url):
    return int(url.rstrip("/").rsplit("/", 1)[-1])

def main():
    index = fetch("https://pokeapi.co/api/v2/evolution-chain?limit=1000")["results"]
    with ThreadPoolExecutor(max_workers=12) as pool:
        chains = list(pool.map(lambda r: fetch(r["url"]), index))

    item_decides, form_decides = {}, set()

    def walk(link):
        parent = species_id(link["species"]["url"])
        for child in link["evolves_to"]:
            target = species_id(child["species"]["url"])
            by_item = {}
            for detail in child.get("evolution_details") or []:
                if (detail.get("required_pokemon_form") or {}).get("name"):
                    form_decides.add((parent, target))
                    continue
                form = (detail.get("evolved_pokemon_form") or {}).get("name")
                item = ((detail.get("item") or {}).get("name")
                        or (detail.get("held_item") or {}).get("name"))
                if form and item:
                    by_item.setdefault(item, set()).add(form)
            if len(by_item) > 1 and len({f for s in by_item.values() for f in s}) > 1:
                item_decides[(parent, target)] = sorted(by_item)
            walk(child)

    for chain in chains:
        walk(chain["chain"])

    payload = {
        "itemDecides": [{"from": f, "to": t, "items": items}
                        for (f, t), items in sorted(item_decides.items())],
        "formDecides": [{"from": f, "to": t} for f, t in sorted(form_decides)],
    }
    if not payload["itemDecides"] or not payload["formDecides"]:
        raise SystemExit("한 부류가 0건이다 — 가드가 장식이 된다. 쿼리를 의심하라")
    with open(OUT, "w") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print(f'itemDecides {len(payload["itemDecides"])} · formDecides {len(payload["formDecides"])} -> {OUT}')
```

- [ ] **Step 2: 돌려서 픽스처를 만든다**

Run: `python3 scripts/generate-evolution-form-edges.py`
Expected: `itemDecides` 2건(868→869, 891→892), `formDecides` 2건(854→855, 1012→1013).
**둘 다 0이 아닌 것을 눈으로 확인한다.**

- [ ] **Step 3: 커버리지 테스트를 쓴다**

```swift
/// 조건·결과가 갈리는 간선을 카탈로그가 **다 덮는지.** 데이터가 늘면(새 세대) 여기서 알려 준다.
/// 지금은 각각 2건이고, **0이 아닌 것을 확인했다** — 한 번도 안 걸리는 가드는 장식이다.
final class EvolutionFormCoverageTests: XCTestCase {
    private struct Edge: Decodable { let from: Int; let to: Int }
    private struct Fixture: Decodable { let itemDecides: [Edge]; let formDecides: [Edge] }

    private func fixture() throws -> Fixture {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "form-split-edges", withExtension: "json",
                              subdirectory: "EvolutionForms"),
            "픽스처가 없다 — Package.swift 의 resources 에 Fixtures/EvolutionForms 가 있는지 보라")
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    func testEveryItemDecidedEdgeIsCatalogued() throws {
        for edge in try fixture().itemDecides {
            XCTAssertFalse(EvolvedFormCatalog.all.filter { $0.speciesID == edge.to }.isEmpty,
                           "#\(edge.from)→#\(edge.to) 를 EvolvedFormCatalog 가 모른다")
        }
    }

    func testEveryFormDecidedEdgeHasBirthForms() throws {
        for edge in try fixture().formDecides {
            XCTAssertFalse(BirthFormCatalog.forms(speciesID: edge.from).isEmpty,
                           "#\(edge.from) 의 태생 모습이 없다 — 조건을 가를 축이 없다")
        }
    }

    func testTheSweepFoundSomething() throws {
        XCTAssertFalse(try fixture().itemDecides.isEmpty)
        XCTAssertFalse(try fixture().formDecides.isEmpty)
    }
}
```

- [ ] **Step 4: 폼 이름을 공식 이름표로 잠근다**

`scripts/generate-item-names.py` 에 폼 이름 구역을 더한다. 앱의 변종 슬러그와 PokéAPI 의
`pokemon-form` 슬러그가 다르므로(`alcremie-rubycream` ↔ `alcremie-ruby-cream`) 맵이 필요하다:

```python
# EvolvedFormCatalog 의 슬러그 → PokéAPI pokemon-form 슬러그.
FORM_SLUGS = {
    "urshifu-rapidstrike": "urshifu-rapid-strike",
    "alcremie-rubycream": "alcremie-ruby-cream",
    "alcremie-matchacream": "alcremie-matcha-cream",
    "alcremie-mintcream": "alcremie-mint-cream",
    "alcremie-lemoncream": "alcremie-lemon-cream",
    "alcremie-saltedcream": "alcremie-salted-cream",
    "alcremie-rainbowswirl": "alcremie-rainbow-swirl",
}

def form_names():
    out = {}
    for app_slug, api_slug in FORM_SLUGS.items():
        dto = fetch(f"https://pokeapi.co/api/v2/pokemon-form/{api_slug}")
        by_lang = {n["language"]["name"]: n["name"] for n in dto.get("form_names", [])}
        out[app_slug] = {lang: by_lang[lang] for lang in LANGS if by_lang.get(lang)}
    return out
```

`payload` 에 `"forms": form_names()` 를 더한다. 읽는 쪽은 **`ItemNameTests`** 다(같은 픽스처 파일이다 —
`EvolutionFormCoverageTests` 는 간선 파일만 읽는다). `ItemNameTests.Fixture` 에 필드를 더한다:

```swift
    private struct Fixture: Decodable {
        let official: [String: [String: String]]
        let invented: [String]
        let forms: [String: [String: String]]
    }
```

그리고 테스트를 더한다:

```swift
    /// 폼 이름도 공식 이름표에서 온다 — 도구 이름 87개가 틀렸던 것과 같은 부류다.
    func testEveryEvolvedFormLabelMatchesTheOfficialName() throws {
        let official = try fixture().forms
        for decided in EvolvedFormCatalog.all {
            guard let slug = decided.slug, let label = decided.label else { continue }
            guard let names = official[slug] else {
                return XCTFail("\(slug) 가 픽스처에 없다 — 생성 스크립트를 돌려라")
            }
            if let ko = names["ko"] { XCTAssertEqual(label.ko, ko, slug) }
            if let en = names["en"] { XCTAssertEqual(label.en, en, slug) }
            if let ja = names["ja"] { XCTAssertEqual(label.ja, ja, slug) }
        }
    }
```

**한국어가 없는 폼이 있다**(실측: `polteageist-antique` 의 ko 가 비어 있다). 위 테스트는 `if let`
으로 없는 언어를 건너뛰므로, 그런 항목은 `BirthFormCatalog` 의 기존 관례대로 일본어 원문에서
옮기고 그 사실을 카탈로그 주석에 남긴다(이미 `sinisteaLine` 주석이 그렇게 돼 있다).

**스크립트를 고친 뒤 반드시 돌려서 픽스처를 다시 만든다:**

Run: `python3 scripts/generate-item-names.py`
Expected: `forms` 키가 생긴다. `Fixture.forms` 는 비옵셔널이라 **재생성을 빼먹으면 디코드가
실패해 `ItemNameTests` 가 통째로 깨진다.**

- [ ] **Step 5: 전체 테스트 후 커밋**

Run: `swift test` → 0 실패.

```bash
git add scripts/ Tests/PokeDexBarTests/ Package.swift
git commit -m "test: pin the set of edges whose condition or result splits

Both sweeps return two edges today, and the guards assert that count is not
zero, so they cannot quietly become decoration. A new generation that adds
such an edge fails the coverage test instead of shipping a branch nobody
catalogued."
```

---

## 마무리

- [ ] `swift test` 전체 통과(1617 + 신규, 0 실패)
- [ ] `./scripts/test-gate.sh` 통과
- [ ] **스크린샷**: Task 7 이 `Sources/PokeDexBar/UI/` 를 건드리는 `feat:` 커밋이라 다음 릴리스에서 `release.sh` 의 **신규 에셋 하드 게이트**에 걸린다. 캡처 픽스처(`ScreenshotGenerator.swift` 의 `ScreenshotFixture`)에 치고마나 마빌크가 없으므로 **기존 스크린샷을 다시 그려도 통과하지 않는다** — 도구별 진화 버튼이 보이는 **새 에셋**을 만들어야 한다. 릴리스 담당이 이 줄을 보게 둔다.
- [ ] `superpowers:requesting-code-review` 로 브랜치 전체 리뷰
