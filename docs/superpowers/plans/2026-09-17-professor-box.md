# 박사의 상자 (아이템 뽑기) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 박사 포인트로 도는 아이템 뽑기를 만든다 — 하루 첫 판 무료, 이후 그날 안에서 값이 두 배씩 오르며, 결과는 등급 연출로 열린다.

**Architecture:** 굴림·값·상태는 `PlayerStore` 확장과 순수 타입(`ItemDrawBalance`)에 두고, 화면은 박사 구역의 세 번째 칸 하나만 더한다. 두 배 사다리는 `CharmLadder` 에 박혀 있던 계산을 `DoublingLadder` 로 빼내 공유하고, 연출은 `EggRevealView` 의 무대를 `RevealTheater` 로 빼내 알/아이템이 같이 쓴다. 새 아이템(마사지 쿠폰·세대 확정권 9종)은 기존 `ShopItem` 에 케이스로 들어가 인벤토리·가방·지급 경로를 그대로 탄다.

**Tech Stack:** Swift 6, SwiftPM, SwiftUI, XCTest. 외부 의존성 없음.

**Spec:** `docs/superpowers/specs/2026-09-17-item-draw-design.md` — 계획은 스펙에서 논증하므로 둘을 같이 읽는다.

## Global Constraints

- macOS 14 floor. 외부 의존성 추가 금지.
- 커밋 메시지·PR 제목·PR 본문은 **영어만**. 코드 주석은 한국어.
- 사용자에게 보이는 모든 문자열은 ko/en/ja 세 언어를 `t(ko, en, ja)` 로 함께 선언한다.
- 경고 0 으로 유지한다.
- 확률표는 **정수 천분율**로 선언하고 굴림은 정수 공간에서 누적한다(`EggBalance.rollGrade` 와 같은 이유 — 소수 누적은 경계에서 샌다).
- 산술에 쓰이는 세이브 값은 **디코드 경계 한 곳**에서 범위를 자른다(`PlayerState.init(from:)`).
- 하루가 바뀌는 판정은 `PlayerStore.swift` 의 `todayDate != state.lastDate` 블록 **한 곳**에만 둔다.
- 아이템은 **그 포켓몬의 자기 화면**에서 쓴다. 가방은 보기만 하는 곳이다.
- 테스트는 실제 세이브를 절대 읽거나 쓰지 않는다 — 임시 파일 + `#if DEBUG` 헬퍼.
- 새 가드는 뮤테이션으로 확인한다: 가드를 되돌렸을 때 그 테스트가 **실제로 깨지는지** 보고 되돌린다.
- 값 표: 뽑기 사다리 base **20 포인트**, 풀 가중 합 **정확히 1000‰**, 마사지 쿠폰 **86,400초**.

## File Structure

| 파일 | 책임 |
|---|---|
| `Sources/PokeDexBar/Player/DoublingLadder.swift` (신규) | 두 배 값 사다리. base 에서 상한을 유도한다 |
| `Sources/PokeDexBar/Player/CharmLadder.swift` (수정) | 위 타입에 위임. 외부 시그니처 불변 |
| `Sources/PokeDexBar/Player/ShopItem.swift` (수정) | 마사지 쿠폰 + 세대 확정권 9종, `guaranteedGeneration` |
| `Sources/PokeDexBar/Player/ItemDrawBalance.swift` (신규) | 풀·가중·사다리·굴림 (순수) |
| `Sources/PokeDexBar/Player/PlayerStore+ItemDraw.swift` (신규) | `drawItem()`, `useMassageCoupon(on:)`, 값·무료 판정 |
| `Sources/PokeDexBar/Player/PlayerState.swift` (수정) | `freeItemDrawUsed`·`paidItemDraws` + 경계 자르기 |
| `Sources/PokeDexBar/Player/PlayerStore.swift` (수정) | 하루 경계에서 두 필드 초기화 |
| `Sources/PokeDexBar/UI/RevealTheater.swift` (신규) | 연출 무대 공통부 (배경·링·파티클·단계 진행) |
| `Sources/PokeDexBar/UI/EggRevealView.swift` (수정) | 무대를 `RevealTheater` 에 위임 |
| `Sources/PokeDexBar/UI/ItemRevealView.swift` (신규) | 아이템 결과 연출 |
| `Sources/PokeDexBar/UI/ProfessorBoxSection.swift` (신규) | 박사 구역 세 번째 칸 |
| `Sources/PokeDexBar/UI/ShopTabView.swift` (수정) | 위 칸을 `DailyGoalsView` 아래에 배치 |
| `Sources/PokeDexBar/UI/IndividualDetailView.swift` (수정) | 마사지 쿠폰 사용 버튼 |
| `Sources/PokeDexBar/Core/Localization.swift` (수정) | 새 문자열 |

---

### Task 1: `DoublingLadder` 추출

**Files:**
- Create: `Sources/PokeDexBar/Player/DoublingLadder.swift`
- Modify: `Sources/PokeDexBar/Player/CharmLadder.swift:14-41`
- Test: `Tests/PokeDexBarTests/DoublingLadderTests.swift`

**Interfaces:**
- Consumes: 없음.
- Produces: `struct DoublingLadder { init(base: Int); let base: Int; let maxStep: Int; func price(step: Int) -> Int?; func cumulative(through step: Int) -> Int }`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```swift
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
```

- [ ] **Step 2: 실패를 확인한다**

Run: `swift test --filter DoublingLadderTests`
Expected: 컴파일 실패 — `cannot find 'DoublingLadder' in scope`

- [ ] **Step 3: 타입을 만든다**

`Sources/PokeDexBar/Player/DoublingLadder.swift`:

```swift
import Foundation

/// base 로 시작해 단계마다 두 배가 되는 값 사다리. 부적 단계와 아이템 뽑기가 공유한다.
///
/// **상한은 base 에서 유도한다.** 값이 두 배씩 뛰므로 단계가 커지면 `Int` 를 넘고, Swift 의
/// 곱셈은 트랩이라 프로세스가 죽는다. 부적에서 상한을 손으로 40 이라고 적었다가 실제로
/// 밟았다 — 2.5억 base 의 실제 한계는 35 였다. 상수로 두면 base 를 고칠 때 같이 안 움직인다.
struct DoublingLadder: Sendable {
    let base: Int
    /// 값과 누적이 모두 `Int` 안에 들어가는 가장 큰 단계.
    let maxStep: Int

    init(base: Int) {
        precondition(base > 0, "base must be positive")
        self.base = base
        var step = 1
        // 누적 `base × (2^t − 1)` 이 들어가는 가장 큰 t 를 센다.
        while Int.max / base >= (1 << (step + 1)) - 1 { step += 1 }
        self.maxStep = step
    }

    /// 이 단계를 사는 값. 1단계 미만이거나 상한 밖이면 값이 없다.
    func price(step: Int) -> Int? {
        guard step >= 1, step <= maxStep else { return nil }
        return base * (1 << (step - 1))
    }

    /// 여기까지 오는 데 든 총액 — 화면이 "지금까지 얼마 썼나" 를 보여줄 때 쓴다.
    func cumulative(through step: Int) -> Int {
        guard step >= 1 else { return 0 }
        return base * ((1 << min(step, maxStep)) - 1)
    }
}
```

- [ ] **Step 4: 통과를 확인한다**

Run: `swift test --filter DoublingLadderTests`
Expected: PASS

- [ ] **Step 5: `CharmLadder` 가 이 타입에 위임하게 바꾼다**

`CharmLadder` 안의 `price(tier:)`·`cumulative(through:)`·`maxSafeTier`·`pow2` 를 아래로 바꾼다. **외부 시그니처는 그대로 둔다** — 호출부와 기존 테스트가 안 바뀌어야 그 테스트들이 추출의 회귀 가드가 된다.

```swift
    /// 값 사다리 — 계산은 `DoublingLadder` 가 한다(아이템 뽑기와 공유).
    static let ladder = DoublingLadder(base: basePrice)

    /// 이 단계를 사는 값. 1단계 미만은 값이 없다.
    static func price(tier: Int) -> Int? { ladder.price(step: tier) }

    /// 여기까지 올리는 데 든 총액 — 화면이 "지금까지 얼마 썼나" 를 보여줄 때 쓴다.
    static func cumulative(through tier: Int) -> Int { ladder.cumulative(through: tier) }

    /// 오버플로 방어의 상한. `basePrice` 에서 유도되므로 값을 고치면 같이 움직인다.
    static var maxSafeTier: Int { ladder.maxStep }
```

`private static func pow2(_:)` 는 다른 데서 안 쓰이면 지운다. 쓰이면 남긴다 — `grep -n "pow2" Sources/` 로 확인한다.

- [ ] **Step 6: 기존 부적 테스트가 그대로 통과하는지 본다**

Run: `swift test --filter CharmLadderTests`
Expected: PASS — 이 테스트들이 추출이 동작을 안 바꿨다는 증거다.

- [ ] **Step 7: 뮤테이션으로 가드를 확인한다**

`DoublingLadder.init` 의 `while` 조건을 `while step < 40` 으로 바꾸고 `swift test --filter "DoublingLadderTests|CharmLadderTests"` 를 돌린다. 깨지는 것을 확인한 뒤 되돌린다.

- [ ] **Step 8: 커밋**

```bash
git add Sources/PokeDexBar/Player/DoublingLadder.swift Sources/PokeDexBar/Player/CharmLadder.swift Tests/PokeDexBarTests/DoublingLadderTests.swift
git commit -m "refactor: extract the doubling price ladder out of CharmLadder"
```

---

### Task 2: 새 아이템 — 마사지 쿠폰과 세대 확정권 9종

**Files:**
- Modify: `Sources/PokeDexBar/Player/ShopItem.swift`
- Test: `Tests/PokeDexBarTests/ItemCatalogTests.swift`

**Interfaces:**
- Consumes: 없음.
- Produces: `ShopItem.massageCoupon`, `ShopItem.gen1EggTicket` … `gen9EggTicket`, `var guaranteedGeneration: Int?`, `static func generationTicket(for generation: Int) -> ShopItem?`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```swift
import XCTest
@testable import PokeDexBar

/// 새 아이템 — 분류·수급처·세대 대응.
final class ItemCatalogTests: XCTestCase {
    /// 뽑기·미션으로만 들어온다. 상점에 서면 이 뽑기를 돌 이유가 사라진다.
    func testTheNewItemsAreNotSoldInTheShop() {
        XCTAssertFalse(ShopItem.massageCoupon.isSold)
        for generation in 1...9 {
            let ticket = ShopItem.generationTicket(for: generation)
            XCTAssertNotNil(ticket, "\(generation)세대 확정권이 없다")
            XCTAssertFalse(ticket!.isSold, "\(generation)세대 확정권이 상점에 선다")
        }
    }

    /// 쓰면 없어지는 것이라 소모품 칸이다 — 부적 칸에 서면 개수를 안 센다.
    func testTheNewItemsAreConsumables() {
        XCTAssertEqual(ShopItem.massageCoupon.category, .consumable)
        XCTAssertTrue(ShopItem.massageCoupon.isConsumable)
        for generation in 1...9 {
            XCTAssertEqual(ShopItem.generationTicket(for: generation)?.category, .consumable)
        }
    }

    /// 세대권 ↔ 세대 번호가 양방향으로 맞물린다. 한쪽만 맞으면 8세대권이 7세대를 연다.
    func testGenerationTicketsRoundTrip() {
        for generation in 1...9 {
            let ticket = ShopItem.generationTicket(for: generation)
            XCTAssertEqual(ticket?.guaranteedGeneration, generation, "\(generation)세대")
        }
        XCTAssertNil(ShopItem.generationTicket(for: 0))
        XCTAssertNil(ShopItem.generationTicket(for: 10))
    }

    /// 세대권이 아닌 것에는 세대가 없다 — 대조군. 없으면 "전부 1을 돌려준다"도 통과한다.
    func testOtherItemsHaveNoGeneration() {
        for item in [ShopItem.expCandy, .massageCoupon, .rareEggTicket, .legendaryEggTicket] {
            XCTAssertNil(item.guaranteedGeneration, "\(item.rawValue)")
        }
    }

    /// 세대권은 **등급을 보장하지 않는다** — 세대만 한정하는 쿠폰이다.
    func testGenerationTicketsGuaranteeNoGrade() {
        for generation in 1...9 {
            XCTAssertNil(ShopItem.generationTicket(for: generation)?.guaranteedGrade)
        }
    }

    /// 모든 언어에 이름과 설명이 있다. 빠지면 그 언어에서 빈 줄이 선다.
    func testEveryNewItemIsNamedInEveryLanguage() {
        var items: [ShopItem] = [.massageCoupon]
        items += (1...9).compactMap { ShopItem.generationTicket(for: $0) }
        for item in items {
            for language in [AppLanguage.ko, .en, .ja] {
                XCTAssertFalse(item.label(language).isEmpty, "\(item.rawValue) \(language) 이름")
                XCTAssertFalse(item.detail(language).isEmpty, "\(item.rawValue) \(language) 설명")
            }
        }
    }

    /// 세대권 아홉 개의 이름이 서로 다르다 — 복사해 붙이며 세대 숫자를 안 고친 것을 잡는다.
    func testGenerationTicketNamesAreDistinct() {
        let names = (1...9).compactMap { ShopItem.generationTicket(for: $0)?.label(.ko) }
        XCTAssertEqual(Set(names).count, 9, "\(names)")
    }
}
```

- [ ] **Step 2: 실패를 확인한다**

Run: `swift test --filter ItemCatalogTests`
Expected: 컴파일 실패 — `type 'ShopItem' has no member 'massageCoupon'`

- [ ] **Step 3: 케이스를 더한다**

`ShopItem` 의 `case rareEggTicket, epicEggTicket, legendaryEggTicket` 아래에 붙인다:

```swift
    /// 마사지 쿠폰 — 한 마리의 친밀도를 24시간만큼 올린다. **팔지 않는다**(박사의 상자에서만).
    /// 본가의 마사지(친밀도를 올려 주는 시설)에서 온 이름이다.
    case massageCoupon
    /// 세대 알 확정권 — **그 세대의 종만** 나오는 알 한 개. 등급은 평소 확률로 굴린다.
    /// 등급 확정권과 달리 세대만 한정하므로 `guaranteedGrade` 는 nil 이다.
    case gen1EggTicket, gen2EggTicket, gen3EggTicket, gen4EggTicket, gen5EggTicket
    case gen6EggTicket, gen7EggTicket, gen8EggTicket, gen9EggTicket
```

- [ ] **Step 4: `price`·`isSold` 에 넣는다**

`price` 의 `case .rainbowCharm, .rareEggTicket, .epicEggTicket, .legendaryEggTicket: Int.max` 줄과 `isSold` 의 같은 줄에 새 케이스를 더한다. 나열이 길어지므로 세대권은 `guaranteedGeneration != nil` 로 접는다:

```swift
    var price: Int {
        // 못 사는 물건의 값 — 상점 목록에서 빠지므로 표시될 일이 없고, 혹시 새 화면이
        // 실수로 노출해도 살 수 없는 값이다.
        guard isSold else { return Int.max }
        switch self {
        case .expCandy: return 500_000_000
        case .shinyCandy: return 3_000_000_000
        case .megaStone: return 2_000_000_000
        case .dynamaxMushroom: return 2_000_000_000
        case .shinyCharm: return 3_000_000_000
        case .expCharm: return 4_000_000_000
        case .fortuneCharm: return 5_000_000_000
        default: return Int.max
        }
    }

    /// 상점에 진열되는가. 무지개 부적·확정권·마사지 쿠폰은 보상 전용이라 상점에 안 선다.
    var isSold: Bool {
        switch self {
        case .rainbowCharm, .rareEggTicket, .epicEggTicket, .legendaryEggTicket, .massageCoupon:
            false
        default: guaranteedGeneration == nil
        }
    }
```

- [ ] **Step 5: 세대 대응과 이름·설명을 더한다**

```swift
    /// 세대 확정권이 한정하는 세대. 세대권이 아니면 nil.
    var guaranteedGeneration: Int? {
        switch self {
        case .gen1EggTicket: 1
        case .gen2EggTicket: 2
        case .gen3EggTicket: 3
        case .gen4EggTicket: 4
        case .gen5EggTicket: 5
        case .gen6EggTicket: 6
        case .gen7EggTicket: 7
        case .gen8EggTicket: 8
        case .gen9EggTicket: 9
        default: nil
        }
    }

    /// 세대 → 그 세대의 확정권. 없는 세대면 nil.
    static func generationTicket(for generation: Int) -> ShopItem? {
        allCases.first { $0.guaranteedGeneration == generation }
    }
```

`label(_:)` 의 switch 에 더한다:

```swift
        case .massageCoupon: names = ("마사지 쿠폰", "Massage Coupon", "マッサージけん")
        case .gen1EggTicket, .gen2EggTicket, .gen3EggTicket, .gen4EggTicket, .gen5EggTicket,
             .gen6EggTicket, .gen7EggTicket, .gen8EggTicket, .gen9EggTicket:
            // 세대 숫자는 값에서 온다 — 아홉 줄을 손으로 적으면 하나가 어긋난다.
            let generation = guaranteedGeneration ?? 0
            names = ("\(generation)세대 알 확정권",
                     "Gen \(generation) Egg Ticket",
                     "\(generation)せだいタマゴかくていけん")
```

`detail(_:)` 의 switch 에 더한다:

```swift
        case .massageCoupon:
            texts = ("지정한 포켓몬과 함께한 시간을 24시간 늘립니다",
                     "Adds 24 hours to the time you have spent with a chosen Pokémon",
                     "指定したポケモンと過ごした時間を24時間増やします")
        case .gen1EggTicket, .gen2EggTicket, .gen3EggTicket, .gen4EggTicket, .gen5EggTicket,
             .gen6EggTicket, .gen7EggTicket, .gen8EggTicket, .gen9EggTicket:
            let generation = guaranteedGeneration ?? 0
            texts = ("그 세대의 포켓몬만 나오는 알 한 개 (등급은 평소대로)",
                     "One egg that can only hatch a Gen \(generation) Pokémon (grade rolls as usual)",
                     "そのせだいのポケモンだけが生まれるタマゴ1個（グレードはいつも通り）")
```

- [ ] **Step 6: 통과를 확인하고 전체를 돌린다**

Run: `swift test --filter ItemCatalogTests` → PASS
Run: `swift test` → 기존 테스트 전부 통과. 상점 목록·가방 목록이 `allCases` 를 도는 곳이 있으므로 여기서 회귀가 드러난다.

- [ ] **Step 7: 뮤테이션으로 가드를 확인한다**

`guaranteedGeneration` 의 `case .gen8EggTicket: 8` 을 `7` 로 바꿔 `testGenerationTicketsRoundTrip` 이 깨지는 것을 확인하고 되돌린다.

- [ ] **Step 8: 커밋**

```bash
git add Sources/PokeDexBar/Player/ShopItem.swift Tests/PokeDexBarTests/ItemCatalogTests.swift
git commit -m "feat: add the massage coupon and nine generation egg tickets"
```

---

### Task 3: 마사지 쿠폰 사용

**Files:**
- Create: `Sources/PokeDexBar/Player/PlayerStore+ItemDraw.swift`
- Modify: `Sources/PokeDexBar/UI/IndividualDetailView.swift` (`candySection`)
- Modify: `Sources/PokeDexBar/Core/Localization.swift`
- Test: `Tests/PokeDexBarTests/MassageCouponTests.swift`

**Interfaces:**
- Consumes: `ShopItem.massageCoupon` (Task 2).
- Produces: `PlayerStore.useMassageCoupon(on individualID: UUID) -> Bool`, `L.useMassageCoupon(_ count: Int) -> String`.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```swift
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
}
```

- [ ] **Step 2: `grantForTesting` 이 있는지 확인하고, 없으면 만든다**

Run: `grep -rn "func grantForTesting" Sources/PokeDexBar/`
있으면 그대로 쓴다. 없으면 `PlayerStore` 의 `#if DEBUG` 헬퍼 옆에 더한다:

```swift
    /// 테스트·개발용 아이템 지급. 세이브를 직접 고치는 대신 이 경로를 쓴다.
    func grantForTesting(_ item: ShopItem, count: Int) {
        mutate { $0.inventory[item.rawValue, default: 0] += count }
    }
```

- [ ] **Step 3: 실패를 확인한다**

Run: `swift test --filter MassageCouponTests`
Expected: 컴파일 실패 — `value of type 'PlayerStore' has no member 'useMassageCoupon'`

- [ ] **Step 4: 사용 함수를 만든다**

`Sources/PokeDexBar/Player/PlayerStore+ItemDraw.swift` 를 만들고:

```swift
import Foundation

/// 박사의 상자 — 아이템 뽑기와 거기서 나오는 것들의 사용.
extension PlayerStore {
    /// 마사지 쿠폰 한 장을 쓴다. 그 아이와 **함께한 시간**을 24시간 늘린다.
    ///
    /// `partnerSeconds` 가 아니라 `pettedSeconds` 에 담는 이유는 쓰다듬기와 같다 — 파트너
    /// 시간에 더하면 화면의 "함께한 시간" 까지 늘어 실제로 곁에 있던 시간을 거짓으로 말한다.
    /// 문턱 판정만 `bondDuration` 이 둘을 합쳐 본다.
    ///
    /// 차감과 적용이 한 `mutate` 안에 있다 — 갈라 두면 "쿠폰은 없어졌는데 안 올랐다" 가 난다.
    @discardableResult
    func useMassageCoupon(on individualID: UUID) -> Bool {
        guard count(of: .massageCoupon) > 0,
              let index = state.box.firstIndex(where: { $0.id == individualID }) else { return false }
        mutate {
            $0.box[index].pettedSeconds += ItemDrawBalance.massageSeconds
            Self.consume(.massageCoupon, in: &$0)
        }
        return true
    }
}
```

`ItemDrawBalance` 는 Task 5 에서 만들지만 이 상수만 먼저 필요하므로, `Sources/PokeDexBar/Player/ItemDrawBalance.swift` 를 지금 만들고 상수 하나만 넣는다:

```swift
import Foundation

/// 박사의 상자 — 값·확률·효과량. 화면과 스토어가 이 한 곳에서 값을 읽는다.
enum ItemDrawBalance {
    /// 마사지 쿠폰 한 장이 올려 주는 친밀도(초). 하루치이고, 친밀도 진화 문턱과 같은 값이다
    /// (`EvoRequirement.friendshipSeconds`). 쓰다듬기로는 8분이면 같은 양이 나온다.
    static let massageSeconds = 86_400
}
```

- [ ] **Step 5: 통과를 확인한다**

Run: `swift test --filter MassageCouponTests`
Expected: PASS

- [ ] **Step 6: 상수가 문턱과 어긋나지 않게 잠근다**

`MassageCouponTests` 에 더한다:

```swift
    /// 쿠폰 값과 진화 문턱이 같은 값이라는 것을 못 박는다 — 한쪽만 바뀌면 "한 장이면 된다" 가
    /// 조용히 거짓이 된다.
    func testTheCouponMatchesTheFriendshipThreshold() {
        XCTAssertEqual(ItemDrawBalance.massageSeconds, EvoRequirement.friendshipSeconds)
    }
```

- [ ] **Step 7: 개체 화면에 버튼을 단다**

`Localization.swift` 에 `useExpCandy` 옆에 더한다:

```swift
    /// 마사지 쿠폰 버튼 — 남은 장수를 함께 적는다(사탕 버튼과 같은 관례).
    func useMassageCoupon(_ count: Int) -> String {
        t("마사지 쿠폰 쓰기 (\(count))", "Use Massage Coupon (\(count))",
          "マッサージけんを使う (\(count))")
    }
```

`IndividualDetailView.candySection` 의 `shinyCandies` 블록 다음에 더한다. 조건은 **재고뿐**이다 — 친밀도는 상한이 없어서 언제 써도 효과가 있다:

```swift
            // 친밀도는 상한이 없어 언제 써도 효과가 있다 — 사탕들처럼 "쓸 데가 없는" 상태가
            // 없으므로 재고만 보면 된다.
            if store.count(of: .massageCoupon) > 0 {
                CandyButton(title: l.useMassageCoupon(store.count(of: .massageCoupon))) {
                    _ = store.useMassageCoupon(on: individual.id)
                }
            }
```

`if expCandies > 0 || shinyCandies > 0` 게이트 안에 넣으면 사탕이 없을 때 쿠폰 버튼이 사라진다. 게이트를 `if expCandies > 0 || shinyCandies > 0 || store.count(of: .massageCoupon) > 0` 로 넓힌다.

- [ ] **Step 8: 전체를 돌리고 커밋**

Run: `swift test`
Expected: 전부 통과

```bash
git add Sources/PokeDexBar/Player/PlayerStore+ItemDraw.swift Sources/PokeDexBar/Player/ItemDrawBalance.swift Sources/PokeDexBar/UI/IndividualDetailView.swift Sources/PokeDexBar/Core/Localization.swift Tests/PokeDexBarTests/MassageCouponTests.swift
git commit -m "feat: spend a massage coupon on a Pokemon for a day of friendship"
```

---

### Task 4: 세대 확정권 개봉

**Files:**
- Modify: `Sources/PokeDexBar/Player/EggBalance.swift`
- Modify: `Sources/PokeDexBar/UI/EggSlotsView.swift` (`drawWithTicket`)
- Test: `Tests/PokeDexBarTests/GenerationTicketTests.swift`

**Interfaces:**
- Consumes: `ShopItem.guaranteedGeneration` (Task 2).
- Produces: `EggBalance.speciesIndex(_ index: [BaseSpecies], inGeneration generation: Int) -> [BaseSpecies]`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```swift
import XCTest
@testable import PokeDexBar

/// 세대 확정권 — 그 세대의 종만 나온다.
final class GenerationTicketTests: XCTestCase {
    /// 실제 인덱스를 흉내 낸 후보 목록. 세대마다 여러 마리, 등급도 섞여 있다.
    /// `BaseSpecies` 의 실제 생성자를 쓴다 — 손으로 만든 모양은 증거가 아니다.
    private func index() -> [BaseSpecies] {
        // 각 세대의 첫 종과 마지막 종, 그리고 그 세대의 전설 하나씩.
        let ids = [1, 151, 152, 251, 252, 386, 387, 493, 494, 649,
                   650, 721, 722, 809, 810, 905, 906, 1025]
        return ids.map { BaseSpecies(id: $0, captureRate: 45, isLegendary: false) }
    }

    func testEveryGenerationFiltersToItsOwnRange() {
        for generation in 1...9 {
            let range = DexMissions.generations[generation]!
            let filtered = EggBalance.speciesIndex(index(), inGeneration: generation)
            XCTAssertFalse(filtered.isEmpty, "\(generation)세대 후보가 비었다")
            for species in filtered {
                XCTAssertTrue(range.contains(species.id),
                              "\(generation)세대 티켓이 \(species.id) 를 냈다")
            }
        }
    }

    /// 거르고 나서 뽑아도 그 세대 안이다 — 거르기와 선택을 이어 붙였을 때가 진짜 질문이다.
    func testPickingFromAFilteredIndexStaysInTheGeneration() {
        for generation in 1...9 {
            let range = DexMissions.generations[generation]!
            let filtered = EggBalance.speciesIndex(index(), inGeneration: generation)
            for step in 0..<50 {
                let picked = EggBalance.pickSpecies(from: filtered, grade: .common,
                                                    roll: Double(step) / 50)
                XCTAssertTrue(range.contains(picked),
                              "\(generation)세대에서 \(picked) 가 나왔다")
            }
        }
    }

    /// 대조군: 안 거른 인덱스는 범위 밖도 낸다. 없으면 "거르기가 아무것도 안 해도" 위가 통과한다.
    func testAnUnfilteredIndexDoesLeaveTheGeneration() {
        let range = DexMissions.generations[1]!
        let picks = (0..<50).map {
            EggBalance.pickSpecies(from: index(), grade: .common, roll: Double($0) / 50)
        }
        XCTAssertTrue(picks.contains { !range.contains($0) },
                      "안 거른 인덱스가 1세대만 냈다 — 이 비교는 아무것도 못 잡는다")
    }

    /// 아홉 세대가 전부 도달 가능하다 — 한 세대라도 빈 목록이면 그 티켓이 죽은 티켓이다.
    func testNoGenerationIsEmpty() {
        for generation in 1...9 {
            XCTAssertFalse(EggBalance.speciesIndex(index(), inGeneration: generation).isEmpty,
                           "\(generation)세대")
        }
    }

    /// 없는 세대는 빈 목록 — 호출부가 그걸로 "티켓이 이상하다"를 판단한다.
    func testAnUnknownGenerationFiltersToNothing() {
        XCTAssertTrue(EggBalance.speciesIndex(index(), inGeneration: 0).isEmpty)
        XCTAssertTrue(EggBalance.speciesIndex(index(), inGeneration: 10).isEmpty)
    }
}
```

- [ ] **Step 2: `BaseSpecies` 의 실제 생성자를 확인한다**

Run: `grep -rn "struct BaseSpecies" -A12 Sources/PokeDexBar/`
위 테스트의 `BaseSpecies(id:captureRate:isLegendary:)` 를 실제 시그니처에 맞춘다. 다르면 **테스트를 실제 타입에 맞춘다** — 타입을 테스트에 맞추지 않는다.

- [ ] **Step 3: 실패를 확인한다**

Run: `swift test --filter GenerationTicketTests`
Expected: 컴파일 실패 — `type 'EggBalance' has no member 'speciesIndex'`

- [ ] **Step 4: 거르개를 만든다**

`EggBalance` 에 `pickSpecies` 바로 위에 더한다:

```swift
    /// 후보를 한 세대로 좁힌다 — 세대 확정권이 쓰는 유일한 문이다.
    ///
    /// **`pickSpecies` 를 새로 만들지 않는다.** 그 함수가 종 선택의 유일한 관문이라(상점 뽑기·
    /// 확정권·박사의 제안이 전부 여기를 지난다) 거른 인덱스를 넘기는 것으로 충분하고, 등급이
    /// 빈 풀을 만나면 아래 등급으로 걷는 규칙도 세대 제한을 유지한 채 그대로 적용된다.
    static func speciesIndex(_ index: [BaseSpecies], inGeneration generation: Int) -> [BaseSpecies] {
        guard let range = DexMissions.generations[generation] else { return [] }
        return index.filter { range.contains($0.id) }
    }
```

- [ ] **Step 5: 통과를 확인한다**

Run: `swift test --filter GenerationTicketTests`
Expected: PASS

- [ ] **Step 6: 개봉 경로를 잇는다**

`EggSlotsView.drawWithTicket(_:)` 은 지금 `grade` 만 받는다. 세대권은 등급을 안 정하므로 시그니처를 아이템으로 바꾼다:

```swift
    /// 확정권 한 장을 쓴다. **등급권**은 등급을 고정하고 종은 평소대로 고르며,
    /// **세대권**은 종의 후보를 그 세대로 좁히고 등급은 평소 확률로 굴린다.
    private func drawWithTicket(_ ticket: ShopItem) {
        guard let provider, !drawing else { return }
        drawing = true
        drawError = nil
        drawTask = Task {
            defer { drawing = false }
            guard let index = try? await provider.baseIndex(), !index.isEmpty else {
                drawError = l.drawIndexUnavailable
                return
            }
            let pool = ticket.guaranteedGeneration.map {
                EggBalance.speciesIndex(index, inGeneration: $0)
            } ?? index
            guard !pool.isEmpty else {
                drawError = l.drawIndexUnavailable
                return
            }
            let grade = ticket.guaranteedGrade
                ?? EggBalance.rollGrade(store.nextRandomUnit())
            let chosen = EggBalance.pickSpecies(from: pool, grade: grade,
                                                roll: store.nextRandomUnit())
            guard let egg = store.redeemEggTicket(ticket, grade: grade, speciesID: chosen) else {
                drawError = l.drawNoFreeSlot
                return
            }
            reveal = (grade: egg.grade, shiny: egg.shiny)
        }
    }
```

기존 본문의 성장곡선·성비 인자 전달은 그대로 옮긴다 — `git diff` 로 빠진 인자가 없는지 확인한다.

- [ ] **Step 7: `redeemEggTicket` 이 아이템을 받게 바꾼다**

`PlayerStore+DexMissions.swift` 의 `redeemEggTicket(grade:speciesID:growthRate:genderRate:)` 를 아래로 바꾼다. **차감할 아이템을 등급에서 유도하지 않고 인자로 받는다** — 세대권은 등급에서 유도할 수 없다:

```swift
    /// 확정권 한 장으로 알을 놓는다. 차감할 **아이템을 직접 받는다** — 등급에서 유도하면
    /// 세대권(등급을 안 정한다)이 엉뚱한 등급권을 차감한다.
    @discardableResult
    func redeemEggTicket(_ ticket: ShopItem, grade: Grade, speciesID: Int,
                         growthRate: GrowthRate = .mediumFast,
                         genderRate: Int = GenderBalance.defaultRate) -> Egg? {
        guard count(of: ticket) > 0 else { return nil }
        let shiny = EggBalance.rollShiny(nextRandomUnit(), denominator: shinyDenominator)
        guard let egg = placeEgg(grade: grade, speciesID: speciesID, shiny: shiny,
                                 growthRate: growthRate, genderRate: genderRate) else { return nil }
        mutate { Self.consume(ticket, in: &$0) }
        return egg
    }
```

호출부(`EggSlotsView`, 테스트)를 새 시그니처로 고친다. `grep -rn "redeemEggTicket" Sources Tests` 로 전수 확인한다.

- [ ] **Step 8: 확정권 목록 UI 에 세대권을 넣는다**

`EggSlotsView` 의 `ForEach([ShopItem.rareEggTicket, .epicEggTicket, .legendaryEggTicket], ...)` 를 **값에서 유도**하게 바꾼다 — 손으로 나열하면 세대권 아홉 개를 빠뜨린다:

```swift
            // 가진 확정권만 선다. 목록을 손으로 적으면 새 확정권이 조용히 안 보인다.
            ForEach(ShopItem.allCases.filter {
                ($0.guaranteedGrade != nil || $0.guaranteedGeneration != nil)
                    && store.count(of: $0) > 0
            }, id: \.self) { ticket in
                Button(l.shopTicketDraw(ticket.label(store.language), store.count(of: ticket))) {
                    drawWithTicket(ticket)
                }
                .buttonStyle(.bordered).controlSize(.mini)
                .disabled(store.freeSlots == 0 || drawing)
            }
```

- [ ] **Step 9: 목록이 값에서 유도되는지 테스트로 잠근다**

`GenerationTicketTests` 에 더한다:

```swift
    /// 확정권 목록을 뷰가 손으로 나열하지 않는다 — 나열하면 새 확정권이 조용히 안 보인다.
    func testTheTicketRowIsDerivedNotHandListed() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/PokeDexBar/UI/EggSlotsView.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        // 주석을 먼저 걷어낸다 — 통짜 검색은 바로 위 주석의 같은 낱말에 걸린다.
        let code = source.split(separator: "\n")
            .map { $0.contains("//") ? String($0[..<$0.range(of: "//")!.lowerBound]) : String($0) }
            .joined(separator: "\n")
        XCTAssertFalse(code.contains("[ShopItem.rareEggTicket"), "확정권을 손으로 나열하고 있다")
        XCTAssertTrue(code.contains("guaranteedGeneration != nil"), "세대권이 목록에 안 든다")
    }
```

- [ ] **Step 10: 전체를 돌리고 뮤테이션 확인 후 커밋**

Run: `swift test` → 전부 통과
뮤테이션: `speciesIndex` 의 `filter` 를 `index` 를 그대로 돌려주도록 바꿔 `testPickingFromAFilteredIndexStaysInTheGeneration` 이 깨지는 것을 확인하고 되돌린다.

```bash
git add -A
git commit -m "feat: open a generation egg ticket into that generation only"
```

---

### Task 5: 뽑기 코어 — 풀·사다리·상태

**Files:**
- Modify: `Sources/PokeDexBar/Player/ItemDrawBalance.swift`
- Modify: `Sources/PokeDexBar/Player/PlayerStore+ItemDraw.swift`
- Modify: `Sources/PokeDexBar/Player/PlayerState.swift`
- Modify: `Sources/PokeDexBar/Player/PlayerStore.swift` (하루 경계 블록)
- Test: `Tests/PokeDexBarTests/ItemDrawTests.swift`

**Interfaces:**
- Consumes: `DoublingLadder` (Task 1), `ShopItem.massageCoupon`/`generationTicket(for:)` (Task 2).
- Produces: `ItemDrawBalance.pool: [ItemDrawBalance.Entry]`, `ItemDrawBalance.ladder`, `ItemDrawBalance.roll(_ roll: Double) -> Entry`, `enum ItemPrize`, `PlayerStore.nextItemDrawPrice: Int?`, `PlayerStore.itemDrawIsFree: Bool`, `PlayerStore.drawItem() -> ItemDrawResult?`, `struct ItemDrawResult { let prize: ItemPrize; let item: ShopItem; let count: Int; let rarity: Grade }`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```swift
import XCTest
@testable import PokeDexBar

/// 박사의 상자 — 확률표·사다리·하루 경계.
@MainActor
final class ItemDrawTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeStore(now: @escaping () -> Date) -> PlayerStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("itemdraw-\(UUID().uuidString).json")
        return PlayerStore(fileURL: url, rng: SeededRNG(seed: 11), now: now)
    }

    // MARK: 확률표

    /// 천분율 합이 정확히 1000. 어긋나면 마지막 상품이 새거나 굴림이 표 밖으로 나간다.
    func testTheWeightsSumToExactlyOneThousand() {
        XCTAssertEqual(ItemDrawBalance.pool.reduce(0) { $0 + $1.weight }, 1000)
    }

    func testEveryWeightIsPositive() {
        for entry in ItemDrawBalance.pool {
            XCTAssertGreaterThan(entry.weight, 0, "\(entry.prize)")
        }
    }

    /// 표의 모든 상품이 **실제로 나온다** — 정수 공간 누적이 마지막 항목을 안 흘리는지.
    func testEveryPrizeIsReachable() {
        var seen = Set<String>()
        for step in 0..<10_000 {
            seen.insert(String(describing: ItemDrawBalance.roll(Double(step) / 10_000).prize))
        }
        XCTAssertEqual(seen.count, ItemDrawBalance.pool.count,
                       "도달 못 한 상품이 있다: \(seen)")
    }

    /// 경계 바로 위아래가 서로 다른 상품이다 — 소수 누적이었으면 여기서 샌다.
    func testTheRollNeverFallsOffTheEnd() {
        XCTAssertNotNil(ItemDrawBalance.roll(0.9999).prize)
        XCTAssertNotNil(ItemDrawBalance.roll(1.0).prize)
        XCTAssertNotNil(ItemDrawBalance.roll(0.0).prize)
    }

    /// **반짝이는 사탕은 풀에 없다.** 게임 전체를 통틀어 2개라는 기록된 결정을 잠근다
    /// (`DexMissions.all` 주석). 매일 도는 뽑기에 넣으면 그 결정이 무효가 된다.
    func testShinyCandyIsNotInThePool() {
        for entry in ItemDrawBalance.pool {
            if case .item(let item, _) = entry.prize {
                XCTAssertNotEqual(item, .shinyCandy, "반짝사탕이 뽑기에 들어갔다")
            }
        }
    }

    // MARK: 값 사다리

    func testTheFirstDrawOfTheDayIsFree() {
        let store = makeStore(now: { self.now })
        store.seedForTesting(wallet: 0, slots: 3, eggs: 0, at: now)
        XCTAssertTrue(store.itemDrawIsFree)
        XCTAssertNotNil(store.drawItem(), "포인트가 0인데 무료 판이 안 돌았다")
        XCTAssertFalse(store.itemDrawIsFree)
    }

    func testThePriceDoublesWithinTheDay() {
        let store = makeStore(now: { self.now })
        store.seedForTesting(wallet: 0, slots: 3, eggs: 0, at: now)
        store.grantPointsForTesting(1000)
        _ = store.drawItem()                       // 무료 한 판
        XCTAssertEqual(store.nextItemDrawPrice, 20)
        _ = store.drawItem()
        XCTAssertEqual(store.nextItemDrawPrice, 40)
        _ = store.drawItem()
        XCTAssertEqual(store.nextItemDrawPrice, 80)
    }

    /// 포인트가 모자라면 **nil 이고 아무것도 안 줄어든다.** 제안 데려오기와 같은 규칙이다.
    func testAShortWalletDeductsNothing() {
        let store = makeStore(now: { self.now })
        store.seedForTesting(wallet: 0, slots: 3, eggs: 0, at: now)
        store.grantPointsForTesting(5)
        _ = store.drawItem()                       // 무료 한 판
        let before = store.state.researchPoints
        XCTAssertNil(store.drawItem(), "5점으로 20점짜리를 뽑았다")
        XCTAssertEqual(store.state.researchPoints, before)
        XCTAssertEqual(store.state.paidItemDraws, 0, "실패한 판이 세어졌다")
    }

    func testAPaidDrawDeductsExactlyThePrice() {
        let store = makeStore(now: { self.now })
        store.seedForTesting(wallet: 0, slots: 3, eggs: 0, at: now)
        store.grantPointsForTesting(100)
        _ = store.drawItem()                       // 무료
        XCTAssertNotNil(store.drawItem())          // 20점
        XCTAssertEqual(store.state.researchPoints, 80)
    }

    /// 뽑은 것이 **실제로 가방에 들어간다** — 차감만 되고 물건이 없으면 안 된다.
    func testThePrizeLandsInTheBag() {
        let store = makeStore(now: { self.now })
        store.seedForTesting(wallet: 0, slots: 3, eggs: 0, at: now)
        let result = store.drawItem()
        let prize = try! XCTUnwrap(result)
        XCTAssertGreaterThanOrEqual(store.count(of: prize.item), prize.count)
    }

    // MARK: 하루 경계

    /// 날짜가 바뀌면 무료와 유료 카운터가 **둘 다** 초기화된다. 하나만 비면 값이 안 내려간다.
    func testTheDayRolloverResetsBothCounters() {
        var clock = now
        let store = makeStore(now: { clock })
        store.seedForTesting(wallet: 0, slots: 3, eggs: 0, at: clock)
        store.grantPointsForTesting(1000)
        _ = store.drawItem()
        _ = store.drawItem()
        XCTAssertFalse(store.itemDrawIsFree)
        XCTAssertEqual(store.state.paidItemDraws, 1)

        clock = now.addingTimeInterval(86_400)
        store.update(todayTokens: 0, hasUsageData: true)
        XCTAssertTrue(store.itemDrawIsFree, "다음 날인데 무료가 안 돌아왔다")
        XCTAssertEqual(store.state.paidItemDraws, 0, "다음 날인데 값이 안 내려갔다")
    }

    /// 초기화가 **하루 경계 그 한 곳**에서 일어난다. 판정이 두 곳이면 반드시 갈린다.
    func testTheResetLivesWithTheOtherDailyLedgers() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/PokeDexBar/Player/PlayerStore.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        // 주석을 먼저 걷어낸다 — 통짜 검색은 바로 위 주석의 같은 낱말에 걸려, 코드를 지워도 통과한다.
        let code = source.split(separator: "\n")
            .map { $0.contains("//") ? String($0[..<$0.range(of: "//")!.lowerBound]) : String($0) }
            .joined(separator: "\n")
        XCTAssertTrue(code.contains("freeItemDrawUsed = false"), "무료권 초기화가 없다")
        XCTAssertTrue(code.contains("paidItemDraws = 0"), "유료 카운터 초기화가 없다")
    }

    // MARK: 경계 검증

    /// 봉인이 깨진 세이브의 큰 값이 `1 << n` 에 들어가면 오버플로 트랩으로 프로세스가 죽는다.
    func testATamperedCounterIsClamped() throws {
        let state = try PlayerStateFixture.decoded(paidItemDraws: Int.max)
        XCTAssertLessThanOrEqual(state.paidItemDraws, ItemDrawBalance.ladder.maxStep)
        XCTAssertGreaterThanOrEqual(state.paidItemDraws, 0)
        let negative = try PlayerStateFixture.decoded(paidItemDraws: -5)
        XCTAssertEqual(negative.paidItemDraws, 0)
    }
}
```

- [ ] **Step 2: 테스트 헬퍼 두 개를 확인하거나 만든다**

Run: `grep -rn "func grantPointsForTesting\|enum PlayerStateFixture" Sources Tests`

`grantPointsForTesting` 이 없으면 `PlayerStore` 의 `#if DEBUG` 블록에 더한다:

```swift
    /// 테스트·개발용 박사 포인트 지급.
    func grantPointsForTesting(_ points: Int) {
        mutate { $0.researchPoints = min(ReleaseBalance.maxPoints, $0.researchPoints + points) }
    }
```

`PlayerStateFixture` 가 없으면 `Tests/PokeDexBarTests/PlayerStateFixture.swift` 를 만든다. **실제 세이브를 안 건드린다** — JSON 을 만들어 실제 디코더에 통과시킨다:

```swift
import Foundation
@testable import PokeDexBar

/// 경계 검증 테스트용 — 임의의 값을 넣은 세이브 JSON 을 **실제 디코더**에 통과시킨다.
/// 손으로 만든 `PlayerState` 는 디코드 경로를 안 지나므로 자르기를 검증하지 못한다.
enum PlayerStateFixture {
    static func decoded(paidItemDraws: Int) throws -> PlayerState {
        let json = "{\"paidItemDraws\": \(paidItemDraws)}"
        return try JSONDecoder().decode(PlayerState.self, from: Data(json.utf8))
    }
}
```

세이브가 관대 디코딩이라 나머지 필드가 없어도 기본값으로 채워진다. 안 되면 `PlayerState()` 를 인코딩해 그 딕셔너리의 `paidItemDraws` 만 바꿔 다시 디코딩하는 방식으로 고친다.

- [ ] **Step 3: 실패를 확인한다**

Run: `swift test --filter ItemDrawTests`
Expected: 컴파일 실패 — `type 'ItemDrawBalance' has no member 'pool'`

- [ ] **Step 4: 풀과 굴림을 만든다**

`ItemDrawBalance.swift` 에 더한다:

```swift
/// 상자에서 나오는 것. 세대권은 뽑는 순간 세대를 굴리므로 표에 아홉 줄을 세우지 않는다.
enum ItemPrize: Equatable, Sendable {
    case item(ShopItem, Int)
    case generationTicket
}

extension ItemDrawBalance {
    /// 상품 한 줄. `weight` 는 **정수 천분율**이고 이것이 유일한 선언이다.
    struct Entry: Sendable {
        let prize: ItemPrize
        let weight: Int
        /// 연출 단계 — 알 뽑기와 같은 사다리를 쓴다.
        let rarity: Grade
    }

    /// 하루 첫 판 다음부터의 값 사다리. 그날 안에서 두 배씩 오른다.
    ///
    /// **값을 고정하면 경제가 뚫린다.** 포인트는 개체 방출로 버는데, 알 하나(1천만 토큰)에서
    /// 나온 안 키운 커먼이 2점이라 1천만 토큰 ≈ 2~3점이다. 값이 20 고정이면 한 판의 입력이
    /// 약 8천만 토큰인데 이 풀의 기대값은 그보다 크고, 3슬롯 × 30분이면 하루 100~150점이
    /// 나와 하루 일곱 판까지 도는 순환이 생긴다. 두 배씩 오르면 같은 사람이 네 판에서 멈춘다.
    static let ladder = DoublingLadder(base: 20)

    /// 확률표. 합은 정확히 1000‰ 이고 테스트가 그것을 잠근다.
    ///
    /// **반짝이는 사탕은 없다** — 게임 전체를 통틀어 2개라는 결정이 이미 있다(`DexMissions.all`).
    static let pool: [Entry] = [
        Entry(prize: .item(.expCandy, 1),           weight: 340, rarity: .common),
        Entry(prize: .item(.massageCoupon, 1),      weight: 300, rarity: .common),
        Entry(prize: .generationTicket,             weight: 180, rarity: .rare),
        Entry(prize: .item(.rareEggTicket, 1),      weight: 120, rarity: .rare),
        Entry(prize: .item(.epicEggTicket, 1),      weight:  45, rarity: .epic),
        Entry(prize: .item(.legendaryEggTicket, 1), weight:  15, rarity: .legendary),
    ]

    /// 0…1 굴림 → 상품. **정수 천분율 공간에서 누적한다** — 소수로 누적하면 이진 소수에서
    /// 오차가 쌓여 경계 바로 위 값이 한 줄 아래로 샌다(`EggBalance.rollGrade` 와 같은 이유).
    static func roll(_ roll: Double) -> Entry {
        let clamped = min(1, max(0, roll))
        let scaled = Int(clamped * 1000)
        var cumulative = 0
        for entry in pool {
            cumulative += entry.weight
            if scaled < cumulative { return entry }
        }
        return pool.last!   // 반올림 여분으로 끝까지 온 경우
    }
}
```

- [ ] **Step 5: 세이브 필드를 더한다**

`PlayerState` 에:

```swift
    /// 오늘 무료 한 판을 썼나. 하루 경계에서 비워지는 **로컬 장부**다.
    var freeItemDrawUsed = false
    /// 오늘 유료로 몇 판 뽑았나 — 다음 값이 이 수에서 나온다.
    var paidItemDraws = 0
```

`CodingKeys` 에 두 키를 더하고, `init(from:)` 의 `researchPoints` 줄 옆에 더한다:

```swift
        freeItemDrawUsed = value(.freeItemDrawUsed, false)
        // 관대 디코딩의 짝 — 값 범위 검증. 이 수가 `1 << n` 에 들어가므로 큰 값은 오버플로
        // 트랩으로 프로세스를 죽인다. 상한은 사다리가 감당하는 단계까지다.
        paidItemDraws = min(ItemDrawBalance.ladder.maxStep, max(0, value(.paidItemDraws, 0)))
```

`encode(to:)` 에도 두 필드를 더한다.

- [ ] **Step 6: 하루 경계에서 비운다**

`PlayerStore.swift` 의 `if todayDate != state.lastDate { ... }` 블록에 두 줄을 더한다:

```swift
            state.claimedDailyBonus = false
            // 박사의 상자도 같은 로컬 장부다 — 무료권과 값 사다리가 여기서 함께 내려간다.
            state.freeItemDrawUsed = false
            state.paidItemDraws = 0
```

- [ ] **Step 7: 뽑기 함수를 만든다**

`PlayerStore+ItemDraw.swift` 에 더한다:

```swift
/// 한 판의 결과 — 화면이 연출에 그대로 넘긴다.
struct ItemDrawResult: Equatable, Sendable {
    let prize: ItemPrize
    /// 실제로 가방에 들어간 물건. 세대권은 여기서 세대가 정해져 있다.
    let item: ShopItem
    let count: Int
    let rarity: Grade
}

extension PlayerStore {
    /// 오늘 무료 판이 남았나.
    var itemDrawIsFree: Bool { !state.freeItemDrawUsed }

    /// 다음 판의 값. 무료면 0, 사다리 상한을 넘었으면 nil(더 못 뽑는다).
    var nextItemDrawPrice: Int? {
        if itemDrawIsFree { return 0 }
        return ItemDrawBalance.ladder.price(step: state.paidItemDraws + 1)
    }

    /// 지금 뽑을 수 있나 — 화면의 버튼이 이 하나만 본다.
    var canDrawItem: Bool {
        guard let price = nextItemDrawPrice else { return false }
        return state.researchPoints >= price
    }

    /// 한 판 뽑는다. 못 뽑으면 nil 이고 **아무것도 차감하지 않는다**(제안 데려오기와 같은 규칙).
    ///
    /// 차감·지급·카운터를 한 `mutate` 안에서 한다 — 갈라 두면 "포인트는 줄었는데 물건이 없다"
    /// 나 그 반대가 생긴다(`redeemEggTicket` 이 같은 이유로 한 함수다).
    @discardableResult
    func drawItem() -> ItemDrawResult? {
        guard let price = nextItemDrawPrice, state.researchPoints >= price else { return nil }
        let free = itemDrawIsFree
        let entry = ItemDrawBalance.roll(nextRandomUnit())
        let item: ShopItem
        let count: Int
        switch entry.prize {
        case .item(let shopItem, let n):
            item = shopItem
            count = n
        case .generationTicket:
            // 세대는 여기서 굴린다 — 아홉 세대 균등.
            let generation = 1 + Int(nextRandomUnit() * 9) % 9
            guard let ticket = ShopItem.generationTicket(for: generation) else { return nil }
            item = ticket
            count = 1
        }
        mutate {
            $0.researchPoints -= price
            if free { $0.freeItemDrawUsed = true } else { $0.paidItemDraws += 1 }
            $0.inventory[item.rawValue, default: 0] += count
        }
        return ItemDrawResult(prize: entry.prize, item: item, count: count, rarity: entry.rarity)
    }
}
```

- [ ] **Step 8: 통과를 확인한다**

Run: `swift test --filter ItemDrawTests`
Expected: PASS

- [ ] **Step 9: 세대 굴림이 아홉 세대를 다 내는지 잠근다**

`ItemDrawTests` 에 더한다:

```swift
    /// 세대권이 나왔을 때 아홉 세대가 전부 도달 가능하다 — `% 9` 류의 off-by-one 이면
    /// 한 세대가 영영 안 나온다.
    func testEveryGenerationCanBeDrawn() {
        var seen = Set<Int>()
        for seed in 0..<400 {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("gen-\(UUID().uuidString).json")
            let store = PlayerStore(fileURL: url, rng: SeededRNG(seed: UInt64(seed)),
                                    now: { self.now })
            store.seedForTesting(wallet: 0, slots: 3, eggs: 0, at: now)
            store.grantPointsForTesting(10_000)
            for _ in 0..<6 {
                if let result = store.drawItem(), let g = result.item.guaranteedGeneration {
                    seen.insert(g)
                }
            }
        }
        XCTAssertEqual(seen, Set(1...9), "안 나오는 세대가 있다: \(Set(1...9).subtracting(seen))")
    }
```

- [ ] **Step 10: 뮤테이션으로 가드를 확인하고 커밋**

세 가지를 각각 되돌려 각각 깨지는 것을 확인한다:
1. `pool` 의 `weight: 15` 를 `14` 로 → `testTheWeightsSumToExactlyOneThousand` 깨짐
2. 하루 경계의 `paidItemDraws = 0` 줄 삭제 → `testTheDayRolloverResetsBothCounters`·`testTheResetLivesWithTheOtherDailyLedgers` 깨짐
3. `drawItem` 의 `guard` 를 지우고 무조건 차감 → `testAShortWalletDeductsNothing` 깨짐

Run: `swift test` → 전부 통과

```bash
git add -A
git commit -m "feat: draw an item from the Professor's Box with research points"
```

---

### Task 6: 연출 무대 추출

**Files:**
- Create: `Sources/PokeDexBar/UI/RevealTheater.swift`
- Modify: `Sources/PokeDexBar/UI/EggRevealView.swift`
- Test: `Tests/PokeDexBarTests/DrawRevealCoverTests.swift` (기존 — 그대로 통과해야 한다)

**Interfaces:**
- Consumes: 기존 `RevealStage`, `EggReveal`, `RevealMotion`.
- Produces: `struct RevealBeat { let stage: RevealStage; let beat: Int; let burst: Bool; let finale: Int }`, `struct RevealTheater<Center: View, Result: View>: View`

- [ ] **Step 1: 기존 커버 테스트가 지금 통과하는 것을 확인한다**

Run: `swift test --filter DrawRevealCoverTests`
Expected: PASS — 이것이 추출 전의 기준선이고, 추출 후에도 같아야 한다.

- [ ] **Step 2: 무대를 만든다**

`Sources/PokeDexBar/UI/RevealTheater.swift`:

```swift
import SwiftUI

/// 한 박자의 상태 — 가운데 그림이 이걸 받아 자기 움직임을 만든다.
struct RevealBeat {
    let stage: RevealStage
    /// 매 단계 움츠릴 때 오른다 — `KeyframeAnimator` 의 방아쇠.
    let beat: Int
    /// 링·파티클이 터지는 순간.
    let burst: Bool
    /// 마지막 단계에서 한 번 오른다 — 이로치 반짝임처럼 끝에 한 번만 터뜨릴 것의 방아쇠.
    let finale: Int
}

/// 뽑기 연출의 **무대**. 배경·링·파티클·단계 진행이 여기 살고, 가운데에 서는 그림과 결과 줄만
/// 주입받는다. 알과 아이템이 같은 무대를 쓰는 이유는 갈라 두면 한쪽만 고쳐지기 때문이다.
///
/// 이름이 `RevealStage` 가 아닌 이유: 그 이름은 이미 `EggReveal.stages(for:)` 가 돌려주는
/// **한 단계**를 가리킨다. 같은 이름을 무대 전체에도 붙이면 둘이 섞인다.
struct RevealTheater<Center: View, Result: View>: View {
    let grade: Grade
    let onDone: () -> Void
    @ViewBuilder let center: (RevealBeat) -> Center
    @ViewBuilder let result: (RevealStage) -> Result

    @State private var stageIndex = 0
    @State private var beat = 0
    @State private var burst = false
    @State private var finale = 0
    @State private var showResult = false

    private var stages: [RevealStage] { EggReveal.stages(for: grade) }
    private var stage: RevealStage { stages[min(stageIndex, stages.count - 1)] }

    var body: some View {
        ZStack {
            // **뒤가 비치면 안 된다.** 아래 그라데이션은 가운데가 16% 밖에 안 가려서, 이 연출이
            // 부화칸 줄 위에 뜨면 방금 놓인 알의 등급색과 라벨이 그대로 보였다(사용자 지적) —
            // 연출이 끝나기 전에 결과를 알게 된다. 불투명한 바닥을 깔아 무대의 느낌은 그대로
            // 두고 새는 것만 막는다. `DrawRevealCoverTests` 가 이것을 픽셀로 잠근다.
            Color.black.ignoresSafeArea()
            // 가운데로 시선을 모으는 어둠 — 평평한 검정보다 무대처럼 읽힌다.
            RadialGradient(colors: [stage.color.opacity(0.16), .black.opacity(0.93)],
                           center: .center, startRadius: 0, endRadius: 190)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                ZStack {
                    rings
                    particles
                    center(RevealBeat(stage: stage, beat: beat, burst: burst, finale: finale))
                }
                .frame(width: 150, height: 150)
                if showResult {
                    result(stage).transition(.opacity.combined(with: .offset(y: 8)))
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onDone() }   // 기다리기 싫으면 눌러서 건너뛴다
        .task { await run() }
    }

    // `rings`(EggRevealView.swift:150-160)와 `particles`(같은 파일 163-177)를 **한 글자도
    // 바꾸지 않고** 잘라 붙인다. 둘 다 `stage`·`burst` 만 읽으므로 그대로 컴파일된다.
    // 옮기면서 손대면 추출인지 수정인지 구별할 수 없게 되고, 커버 테스트가 무엇을 잡았는지도 흐려진다.

    /// 단계를 하나씩 지나간다. 각 단계는 예비동작이 끝나는 시점에 터진다 —
    /// 그래야 "움츠렸다가 터졌다"로 읽히고, 동시에 터지면 그냥 깜빡임이 된다.
    private func run() async {
        for index in stages.indices {
            stageIndex = index
            burst = false
            beat += 1
            try? await Task.sleep(for: .seconds(RevealMotion.anticipation))
            if Task.isCancelled { return }
            burst = true
            if index == stages.count - 1 {
                withAnimation(.easeOut(duration: 0.28).delay(0.18)) { showResult = true }
                finale += 1
            }
            let rest = EggReveal.duration(stageIndex: index, of: stages.count)
                - RevealMotion.anticipation
            try? await Task.sleep(for: .seconds(rest))
            if Task.isCancelled { return }
        }
        onDone()
    }
}
```

`rings`·`particles` 의 본문을 `EggRevealView` 에서 잘라 그대로 붙인다.

- [ ] **Step 3: `EggRevealView` 가 무대를 쓰게 바꾼다**

`EggRevealView.body` 를 아래로 바꾸고, `stageIndex`/`beat`/`burst`/`showResult`/`sparkleBeat` 상태와 `rings`/`particles`/`run()` 을 지운다:

```swift
    var body: some View {
        RevealTheater(grade: grade, onDone: onDone) { moment in
            ZStack {
                egg(moment)
                // 이로치는 결과를 말할 때 한 번 더 반짝인다 — 글자보다 이게 먼저 읽힌다.
                if shiny {
                    ShinySparkles(specs: SparkleSpec.ring(count: 9, radius: 0.46),
                                  trigger: moment.finale)
                }
            }
        } result: { stage in
            VStack(spacing: 3) {
                Text(grade.label(language))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(stage.color)
                Text(shiny ? l.drawResultShiny : l.drawResultHatching)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }
```

`egg` 를 `moment` 를 받는 함수로 바꾼다 — `stage`/`beat`/`burst` 가 이제 인자로 온다:

```swift
    private func egg(_ moment: RevealBeat) -> some View {
        KeyframeAnimator(initialValue: EggPose.rest, trigger: moment.beat) { pose in
            EggIcon(grade: moment.stage.grade, size: 78)
                .scaleEffect(pose.scale)
                .rotationEffect(.degrees(pose.rotation))
                .offset(y: pose.lift)
                .shadow(color: moment.stage.color.opacity(0.85), radius: moment.burst ? 22 : 8)
        } keyframes: { _ in
            // EggRevealView.swift:130-148 의 `KeyframeTrack` 세 개(scale·rotation·lift)를
            // **한 글자도 바꾸지 않고** 그대로 옮긴다. 이 트랙들은 `moment` 를 안 읽는다.
        }
    }
```

- [ ] **Step 4: 커버 테스트가 여전히 통과하는지 본다**

Run: `swift test --filter DrawRevealCoverTests`
Expected: PASS — 추출이 화면을 안 바꿨다는 증거다. 깨지면 옮기며 손댄 것이 있다.

- [ ] **Step 5: 전체를 돌린다**

Run: `swift test`
Expected: 전부 통과 (`RevealMotionTests`·`ShinySparklesTests` 포함)

- [ ] **Step 6: 커밋**

```bash
git add Sources/PokeDexBar/UI/RevealTheater.swift Sources/PokeDexBar/UI/EggRevealView.swift
git commit -m "refactor: extract the reveal stage so items can use it too"
```

---

### Task 7: 아이템 연출

**Files:**
- Create: `Sources/PokeDexBar/UI/ItemRevealView.swift`
- Modify: `Sources/PokeDexBar/Core/Localization.swift`
- Test: `Tests/PokeDexBarTests/ItemRevealTests.swift`

**Interfaces:**
- Consumes: `RevealTheater`/`RevealBeat` (Task 6), `ItemDrawResult` (Task 5).
- Produces: `struct ItemRevealView: View` with `init(result: ItemDrawResult, l: L, language: AppLanguage, onDone: @escaping () -> Void)`, `ItemRevealView.symbolName(for: ShopItem) -> String?`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```swift
import XCTest
import SwiftUI
@testable import PokeDexBar

/// 아이템 연출 — 그림 선택과 가림.
@MainActor
final class ItemRevealTests: XCTestCase {
    private static let size = CGSize(width: PopoverMetrics.width, height: 220)

    private func result(_ item: ShopItem, _ rarity: Grade) -> ItemDrawResult {
        ItemDrawResult(prize: .item(item, 1), item: item, count: 1, rarity: rarity)
    }

    /// **쓰는 심볼이 실제로 만들어지는지 API 에 물어본다.** 픽스처가 아니라 그 API 에 묻는
    /// 방식은 이 저장소가 특이행렬 사건에서 택한 것과 같다 — 없는 심볼은 조용히 빈 자리가 된다.
    func testEverySymbolExists() throws {
        for item in ShopItem.allCases {
            guard let name = ItemRevealView.symbolName(for: item) else { continue }
            XCTAssertNotNil(NSImage(systemSymbolName: name, accessibilityDescription: nil),
                            "\(item.rawValue) 의 심볼 \(name) 이 없다")
        }
    }

    /// 알 확정권은 심볼이 아니라 **그 등급의 알 그림**을 쓴다 — 이미 있는 그림이 더 말이 된다.
    func testEggTicketsUseEggArtNotASymbol() {
        for item in [ShopItem.rareEggTicket, .epicEggTicket, .legendaryEggTicket] {
            XCTAssertNil(ItemRevealView.symbolName(for: item), "\(item.rawValue)")
        }
    }

    /// 심볼을 쓰는 것에는 반드시 이름이 있다 — 없으면 아무것도 안 그려진다.
    func testSymbolItemsHaveAName() {
        XCTAssertNotNil(ItemRevealView.symbolName(for: .expCandy))
        XCTAssertNotNil(ItemRevealView.symbolName(for: .massageCoupon))
    }

    private func pixels(behind: Color, item: ShopItem, rarity: Grade) throws -> Data {
        let view = ZStack {
            behind
            ItemRevealView(result: result(item, rarity), l: L(.ko), language: .ko, onDone: {})
        }
        .frame(width: Self.size.width, height: Self.size.height)
        let host = NSHostingView(rootView: view)
        host.appearance = NSAppearance(named: .darkAqua)
        host.frame = CGRect(origin: .zero, size: Self.size)
        host.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.setNeedsDisplay(host.bounds)
        host.displayIfNeeded()
        host.cacheDisplay(in: host.bounds, to: rep)
        let bytes = try XCTUnwrap(rep.bitmapData)
        return Data(bytes: bytes, count: rep.bytesPerRow * rep.pixelsHigh)
    }

    /// 알 연출과 같은 규칙 — 뒤에 무엇을 깔든 결과가 같아야 한다. 비치면 결과를 미리 안다.
    func testTheItemRevealHidesWhateverIsBehindIt() throws {
        let overMagenta = try pixels(behind: Color(red: 1, green: 0, blue: 1),
                                     item: .legendaryEggTicket, rarity: .legendary)
        let overBlack = try pixels(behind: .black, item: .legendaryEggTicket, rarity: .legendary)
        XCTAssertFalse(overMagenta.isEmpty)
        XCTAssertEqual(overMagenta, overBlack, "아이템 연출 뒤가 비친다")
    }
}
```

- [ ] **Step 2: 실패를 확인한다**

Run: `swift test --filter ItemRevealTests`
Expected: 컴파일 실패 — `cannot find 'ItemRevealView' in scope`

- [ ] **Step 3: 문자열을 더한다**

`Localization.swift`:

```swift
    /// 아이템 연출의 아랫줄 — 어디로 갔는지 말한다.
    var itemDrawLanded: String { t("가방에 넣었어요", "Added to your Bag", "バッグに入れました") }
    /// 개수가 둘 이상일 때의 표기.
    func itemDrawCount(_ count: Int) -> String { t("×\(count)", "×\(count)", "×\(count)") }
```

- [ ] **Step 4: 연출을 만든다**

```swift
import SwiftUI

/// 박사의 상자 결과 연출 — 알 뽑기와 **같은 무대**(`RevealTheater`)를 쓰고, 가운데 그림과
/// 결과 줄만 아이템의 것으로 바꾼다.
struct ItemRevealView: View {
    let result: ItemDrawResult
    let l: L
    let language: AppLanguage
    let onDone: () -> Void

    /// 그 아이템을 가리키는 SF Symbol. **알 확정권은 nil** — 이미 있는 알 그림이 더 말이 된다.
    /// 여기 쓰는 것은 전부 SF Symbols 1.0/2.0 세대라 macOS 14 바닥에도 있다. 테스트가 그것을
    /// 픽스처가 아니라 `NSImage(systemSymbolName:)` 에 직접 물어 확인한다.
    static func symbolName(for item: ShopItem) -> String? {
        if item.guaranteedGrade != nil || item.guaranteedGeneration != nil { return nil }
        switch item {
        case .massageCoupon: return "hands.sparkles.fill"
        default: return "pills.fill"
        }
    }

    var body: some View {
        RevealTheater(grade: result.rarity, onDone: onDone) { moment in
            glyph(moment)
        } result: { stage in
            VStack(spacing: 3) {
                Text(result.count > 1
                     ? "\(result.item.label(language)) \(l.itemDrawCount(result.count))"
                     : result.item.label(language))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(stage.color)
                    .multilineTextAlignment(.center)
                Text(l.itemDrawLanded).font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }

    /// 가운데 그림. 확정권은 알 그림, 나머지는 심볼이다.
    @ViewBuilder
    private func glyph(_ moment: RevealBeat) -> some View {
        Group {
            if let grade = result.item.guaranteedGrade {
                EggIcon(grade: grade, size: 78)
            } else if result.item.guaranteedGeneration != nil {
                // 세대권은 등급이 안 정해져 있다 — 등급 없는 알(실루엣) 위에 세대 숫자를 얹는다.
                EggIcon(grade: .common, size: 78)
                    .opacity(0)
                    .overlay {
                        if let art = EggIcon.image(for: .common) {
                            Image(nsImage: art).resizable().renderingMode(.template)
                                .interpolation(.high).scaledToFit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .overlay(alignment: .bottom) {
                        Text("\(result.item.guaranteedGeneration ?? 0)")
                            .font(.system(size: 20, weight: .heavy))
                            .foregroundStyle(.white)
                    }
            } else if let name = Self.symbolName(for: result.item) {
                Image(systemName: name)
                    .font(.system(size: 54, weight: .medium))
                    .foregroundStyle(.white)
            }
        }
        .scaleEffect(moment.burst ? 1.12 : 0.94)
        .shadow(color: moment.stage.color.opacity(0.85), radius: moment.burst ? 22 : 8)
        .animation(.spring(duration: 0.3), value: moment.beat)
    }
}
```

- [ ] **Step 5: 통과를 확인한다**

Run: `swift test --filter ItemRevealTests`
Expected: PASS

- [ ] **Step 6: 뮤테이션으로 가드를 확인하고 커밋**

`symbolName` 의 `"pills.fill"` 을 `"not.a.real.symbol"` 로 바꿔 `testEverySymbolExists` 가 깨지는 것을 확인하고 되돌린다.

```bash
git add Sources/PokeDexBar/UI/ItemRevealView.swift Sources/PokeDexBar/Core/Localization.swift Tests/PokeDexBarTests/ItemRevealTests.swift
git commit -m "feat: reveal a drawn item on the same stage as an egg"
```

---

### Task 8: 박사의 상자 화면

**Files:**
- Create: `Sources/PokeDexBar/UI/ProfessorBoxSection.swift`
- Modify: `Sources/PokeDexBar/UI/ShopTabView.swift:25`
- Modify: `Sources/PokeDexBar/Core/Localization.swift`
- Test: `Tests/PokeDexBarTests/ProfessorBoxViewTests.swift`

**Interfaces:**
- Consumes: `PlayerStore.drawItem()`/`nextItemDrawPrice`/`itemDrawIsFree`/`canDrawItem` (Task 5), `ItemRevealView` (Task 7).
- Produces: `struct ProfessorBoxSection: View`, `ProfessorBoxSection.footnote(store:) -> String`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```swift
import XCTest
@testable import PokeDexBar

/// 박사의 상자 화면 — 자리와 안내 문구.
@MainActor
final class ProfessorBoxViewTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeStore() -> PlayerStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("box-\(UUID().uuidString).json")
        let store = PlayerStore(fileURL: url, rng: SeededRNG(seed: 3), now: { self.now })
        store.seedForTesting(wallet: 0, slots: 3, eggs: 0, at: now)
        return store
    }

    /// 상자는 **박사 구역 아래**에 선다 — 포인트를 주는 곳과 쓰는 곳이 떨어져 있으면
    /// 포인트가 무엇에 쓰이는지 알 길이 없다.
    func testTheBoxSitsUnderTheProfessorSections() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/PokeDexBar/UI/ShopTabView.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        let code = source.split(separator: "\n")
            .map { $0.contains("//") ? String($0[..<$0.range(of: "//")!.lowerBound]) : String($0) }
            .joined(separator: "\n")
        let offer = try XCTUnwrap(code.range(of: "ProfessorOfferSection("))
        let goals = try XCTUnwrap(code.range(of: "DailyGoalsView("))
        let box = try XCTUnwrap(code.range(of: "ProfessorBoxSection("))
        XCTAssertLessThan(offer.lowerBound, box.lowerBound, "상자가 제안보다 위에 있다")
        XCTAssertLessThan(goals.lowerBound, box.lowerBound, "상자가 의뢰보다 위에 있다")
    }

    /// 무료 판이 남았으면 그렇게 말한다.
    func testTheFreeDrawIsAnnounced() {
        let store = makeStore()
        XCTAssertEqual(ProfessorBoxSection.footnote(store: store), store.l.itemDrawFreeToday)
    }

    /// 포인트가 모자라면 **왜 못 누르는지** 말한다 — 회색 버튼만 두고 이유를 안 적어
    /// 사용자가 물어볼 곳이 없던 전례가 있다.
    func testAShortWalletSaysWhy() {
        let store = makeStore()
        _ = store.drawItem()                      // 무료 소진
        XCTAssertEqual(ProfessorBoxSection.footnote(store: store),
                       store.l.itemDrawNeedsPoints(20))
    }

    /// 살 수 있으면 값이 아니라 다음 값을 알려 준다 — 대조군. 없으면 "늘 이유만 낸다"도 통과한다.
    func testWithEnoughPointsItShowsThePrice() {
        let store = makeStore()
        store.grantPointsForTesting(1000)
        _ = store.drawItem()
        XCTAssertEqual(ProfessorBoxSection.footnote(store: store), store.l.itemDrawPrice(20))
    }
}
```

- [ ] **Step 2: 문자열을 더한다**

```swift
    var professorBoxTitle: String { t("박사의 상자", "Professor's Box", "はかせのはこ") }
    var itemDrawFreeToday: String {
        t("오늘 한 판은 무료예요", "Today's first draw is free", "きょうの1回はむりょうです")
    }
    func itemDrawPrice(_ points: Int) -> String {
        t("다음 판 \(points)포인트", "Next draw costs \(points) points",
          "つぎは\(points)ポイント")
    }
    func itemDrawNeedsPoints(_ points: Int) -> String {
        t("\(points)포인트가 필요해요", "You need \(points) points", "\(points)ポイントが必要です")
    }
    var itemDrawSoldOut: String {
        t("오늘은 여기까지예요", "That is all for today", "きょうはここまでです")
    }
    var itemDrawButton: String { t("상자 열기", "Open the box", "はこを開ける") }
```

- [ ] **Step 3: 실패를 확인한다**

Run: `swift test --filter ProfessorBoxViewTests`
Expected: 컴파일 실패 — `cannot find 'ProfessorBoxSection' in scope`

- [ ] **Step 4: 화면을 만든다**

```swift
import SwiftUI

/// 박사의 상자 — 박사 포인트로 도는 아이템 뽑기. 제안·의뢰 아래 세 번째 칸이다.
/// 포인트를 주는 곳과 쓰는 곳이 한 구역에 모여 있어야 포인트가 무엇인지 읽힌다.
struct ProfessorBoxSection: View {
    let store: PlayerStore
    @State private var reveal: ItemDrawResult?

    private var l: L { store.l }

    /// 줄 아래 한 줄. 못 누를 때는 **왜 못 누르는지**가 온다 — 회색 버튼만 두면 물어볼 곳이 없다.
    static func footnote(store: PlayerStore) -> String {
        let l = store.l
        guard let price = store.nextItemDrawPrice else { return l.itemDrawSoldOut }
        if store.itemDrawIsFree { return l.itemDrawFreeToday }
        return store.state.researchPoints >= price
            ? l.itemDrawPrice(price) : l.itemDrawNeedsPoints(price)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                ProfessorIcon(size: 14)
                Text(l.professorBoxTitle).font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(l.researchPoints(store.state.researchPoints))
                    .font(.system(size: 9, weight: .medium)).monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Button(l.itemDrawButton) {
                if let result = store.drawItem() { reveal = result }
            }
            .buttonStyle(.bordered).controlSize(.small)
            .disabled(!store.canDrawItem)
            Text(Self.footnote(store: store))
                .font(.system(size: 8)).foregroundStyle(.tertiary)
        }
        .overlay {
            if let reveal {
                ItemRevealView(result: reveal, l: l, language: store.language) {
                    self.reveal = nil
                }
            }
        }
    }
}
```

`ProfessorIcon` 이 있는지 확인한다: `grep -rn "struct ProfessorIcon" Sources/`. 없으면 `Image(systemName: "person.fill")` 로 바꾸되, 그 심볼을 `ItemRevealTests.testEverySymbolExists` 와 같은 방식으로 확인하는 테스트를 더한다.

- [ ] **Step 5: `ShopTabView` 에 배치한다**

`DailyGoalsView(store: store)` 바로 다음 줄에:

```swift
                // 포인트를 주는 곳(제안·의뢰) 바로 아래가 쓰는 곳이다.
                ProfessorBoxSection(store: store)
```

- [ ] **Step 6: 통과를 확인하고 전체를 돌린다**

Run: `swift test --filter ProfessorBoxViewTests` → PASS
Run: `swift test` → 전부 통과

- [ ] **Step 7: 실제 앱에서 눈으로 본다**

```bash
PTB_DEV=1 ./scripts/build-app.sh && open "build/PokeDexBar Dev.app"
```

상점 탭을 열어 상자가 의뢰 아래 서는지, 무료 한 판이 돌고 연출이 뜨는지, 두 번째 판이 20포인트를 요구하는지 확인한다.

- [ ] **Step 8: 커밋**

```bash
git add -A
git commit -m "feat: put the Professor's Box under his offer and requests"
```

---

### Task 9: 문서·스크린샷

**Files:**
- Modify: `Tests/PokeDexBarTests/ScreenshotGenerator.swift`
- Create: `assets/professor-box.png` (생성기가 만든다)
- Modify: `README.md`, `README.ko.md`, `README.ja.md`
- Modify: gh-pages `index.html` (worktree)

**Interfaces:**
- Consumes: `ProfessorBoxSection` (Task 8).
- Produces: `assets/professor-box.png`

> **왜 이 태스크가 필수인가:** `release.sh` 에 **하드 게이트**가 있다 — 직전 태그 이후 `Sources/**/UI/` 를 건드린 `feat:` 커밋이 있는데 `assets/` 에 **새로 추가된** 파일이 없으면 릴리스가 중단된다(프롬프트로 못 넘긴다). 이 계획은 UI 를 건드리는 `feat:` 커밋을 여럿 만들므로, **새 에셋 파일이 하나 있어야 배포가 된다.**

- [ ] **Step 1: 생성기에 배너를 더한다**

`ScreenshotGenerator.swift` 의 `drawSlotBanner()` 옆에 더하고, `try write(png(professorBoxBanner()), "professor-box.png")` 를 배너 목록에 넣는다:

```swift
    /// 박사의 상자 세 상태를 세로로 — 무료, 유료(값 표시), 포인트 부족.
    private func professorBoxBanner() -> some View {
        let now = ScreenshotFixture.now
        func row(points: Int, spent: Bool) -> ProfessorBoxSection {
            let store = PlayerStore(fileURL: FileManager.default.temporaryDirectory
                                        .appendingPathComponent("box-\(UUID().uuidString).json"),
                                    rng: SeededRNG(seed: 9), now: { now },
                                    defaults: UserDefaults(suiteName: "ptb-box-\(UUID().uuidString)")!)
            store.setLanguage(.en)
            store.seedForTesting(wallet: 0, slots: 3, eggs: 0, at: now)
            store.grantPointsForTesting(points)
            if spent { store.mutate { $0.freeItemDrawUsed = true } }
            return ProfessorBoxSection(store: store)
        }
        return VStack(alignment: .leading, spacing: 14) {
            row(points: 120, spent: false)   // 오늘 무료
            row(points: 120, spent: true)    // 다음 판 20포인트
            row(points: 5, spent: true)      // 포인트 부족
        }
        .frame(width: PopoverMetrics.contentWidth)
        .padding(16)
        .background(Color(nsColor: .windowBackgroundColor))
    }
```

- [ ] **Step 2: 스크린샷을 만든다**

```bash
PTB_SCREENSHOTS=1 PTB_APP_VERSION=1.16.2 swift test --filter ScreenshotGeneratorTests
```

"부화 캡처가 얼어붙었다" 로 실패하면 이 환경의 알려진 문제이므로 다시 실행한다.

이번 변경과 무관하게 재인코딩만 달라진 GIF 는 되돌린다:

```bash
git checkout -- assets/floating-pet.gif assets/screenshot-hatch.gif assets/screenshot-home.gif assets/shiny-sparkle.gif assets/screenshot-reveal.gif assets/shiny-banner.gif
git status --porcelain assets/
```

`assets/professor-box.png` 가 **새로 추가된 파일**로 보이는지 확인한다 — 이것이 릴리스 하드 게이트를 통과시키는 것이다.

- [ ] **Step 3: 눈으로 확인한다**

`assets/professor-box.png` 를 열어 세 상태가 구별되는지 본다. 구별이 안 되면(직전 릴리스에서 실제로 밟은 결함) 대비를 고치고 다시 만든다.

- [ ] **Step 4: README 세 개에 기능 카드를 더한다**

`draw-slot.png` 카드 다음에 같은 모양으로 넣는다. 세 언어 모두, alt 텍스트까지.

영어:

```html
<td width="45%" align="center"><img src="assets/professor-box.png" width="300" alt="The Professor's Box in three states: today's free draw, the next draw priced at 20 points, and the same row dimmed when you are short"></td>
<td width="55%" valign="middle">
<h3>🎁 The Professor's Box</h3>
Research points had one use — taking a Pokémon he offers you. Now they also open a box once a day for free, and again within the day at a price that doubles each time: 20, then 40, then 80. Inside are EXP Candy, <b>Massage Coupons</b> that add a day of friendship to one Pokémon, egg tickets by grade, and <b>generation tickets</b> that hatch only from the generation named on them. The doubling is what keeps it honest: points come from releasing Pokémon, so a flat price would turn eggs into candy on a loop.
</td>
```

한국어:

```html
<td width="45%" align="center"><img src="assets/professor-box.png" width="300" alt="박사의 상자 세 상태 — 오늘의 무료 한 판, 20포인트가 붙은 다음 판, 포인트가 모자라 흐려진 같은 줄"></td>
<td width="55%" valign="middle">
<h3>🎁 박사의 상자</h3>
연구 포인트는 쓸 데가 하나뿐이었어요 — 박사가 내민 포켓몬을 데려오는 것. 이제 하루 한 번은 공짜로 상자를 열고, 그날 안에 더 열고 싶으면 값이 두 배씩 붙어요(20 → 40 → 80). 안에는 경험치 사탕, 한 마리의 친밀도를 하루치 올려 주는 <b>마사지 쿠폰</b>, 등급별 알 확정권, 그리고 적힌 세대에서만 부화하는 <b>세대 확정권</b>이 들어 있습니다. 값이 두 배씩 오르는 건 균형 때문이에요 — 포인트는 포켓몬을 보내서 버니까, 값이 고정이면 알을 사탕으로 바꾸는 순환이 하루 종일 돌아요.
</td>
```

일본어:

```html
<td width="45%" align="center"><img src="assets/professor-box.png" width="300" alt="はかせのはこの3つの状態 — きょうのむりょう1回、20ポイントがついた次の1回、ポイントが足りず暗くなった同じ行"></td>
<td width="55%" valign="middle">
<h3>🎁 はかせのはこ</h3>
けんきゅうポイントの使い道はひとつだけでした — はかせが差し出すポケモンを迎えること。これからは1日1回むりょうではこを開けられ、その日のうちにもう一度開けるなら値段が倍ずつ増えます（20 → 40 → 80）。中にはけいけんちアメ、1匹のなかよし度を1日ぶん上げる<b>マッサージけん</b>、グレードごとのタマゴかくていけん、そして書かれたせだいからしか生まれない<b>せだいかくていけん</b>が入っています。倍になるのはバランスのためです — ポイントはポケモンを送って稼ぐので、値段が固定だとタマゴをアメに変える循環が一日中まわります。
</td>
```

- [ ] **Step 5: 랜딩에 반영한다**

```bash
git worktree add /tmp/ptb-ghpages gh-pages
```

`index.html` 에 기능 카드 하나(`draw-slot` 카드 다음)와 **세 언어 사전 모두**에 `cap.box` 키를
같은 자리에 더한다. 카드의 정적 본문은 en 문구를 쓴다:

- `en` → `"cap.box": "Research points had one use — taking a Pokémon the Professor offers. Now they also open a box once a day for free, and again within the day at a price that doubles each time: 20, then 40, then 80. Inside are EXP Candy, Massage Coupons that add a day of friendship to one Pokémon, egg tickets by grade, and generation tickets that hatch only from the generation named on them."`
- `ko` → `"cap.box": "연구 포인트는 쓸 데가 하나뿐이었어요 — 박사가 내민 포켓몬을 데려오는 것. 이제 하루 한 번은 공짜로 상자를 열고, 그날 안에 더 열고 싶으면 값이 두 배씩 붙어요(20 → 40 → 80). 안에는 경험치 사탕, 친밀도를 하루치 올려 주는 마사지 쿠폰, 등급별 알 확정권, 적힌 세대에서만 부화하는 세대 확정권이 들어 있습니다."`
- `ja` → `"cap.box": "けんきゅうポイントの使い道はひとつだけでした — はかせが差し出すポケモンを迎えること。これからは1日1回むりょうではこを開けられ、その日のうちにもう一度開けるなら値段が倍ずつ増えます（20 → 40 → 80）。中にはけいけんちアメ、なかよし度を1日ぶん上げるマッサージけん、グレードごとのタマゴかくていけん、書かれたせだいからしか生まれないせだいかくていけんが入っています。"`

키 정합을 기계로 확인한다:

```bash
python3 - <<'PY'
import re
s = open("/tmp/ptb-ghpages/index.html", encoding="utf-8").read()
heads = [(m.group(1), m.start()) for m in re.finditer(r'^\s*(en|ko|ja)\s*:\s*\{', s, re.M)]
sets = {}
for i, (lang, pos) in enumerate(heads):
    end = heads[i+1][1] if i+1 < len(heads) else len(s)
    sets[lang] = set(re.findall(r'"([^"]+)"\s*:', s[pos:end]))
vals = list(sets.values())
print({k: len(v) for k, v in sets.items()}, "정합:", all(v == vals[0] for v in vals))
PY
```

정합이 True 인 것을 확인하고 커밋·푸시한 뒤 worktree 를 지운다:

```bash
cd /tmp/ptb-ghpages && git add -A && git commit -m "landing: the Professor's Box" && git push origin gh-pages
cd - && git worktree remove /tmp/ptb-ghpages
```

- [ ] **Step 6: 전체를 돌리고 커밋**

Run: `swift test`
Expected: 전부 통과

```bash
git add -A
git commit -m "docs: document the Professor's Box"
```

---

## 완료 후

1. `superpowers:finishing-a-development-branch` 로 브랜치를 정리한다.
2. PR 을 **영어로** 올린다 — `gh pr create --repo donky-ey/PokeDexBar`. 이 저장소는 포크라 `--repo` 를 빼면 상위 저장소(`chattymin/PokeTokenBar`)로 올라간다.
3. 스쿼시 머지 후 `main` 에서 릴리스한다. 버전 세그먼트는 사용자에게 확인받는다 — 새 기능이므로 마이너가 자연스럽다.
