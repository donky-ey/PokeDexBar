# 박사의 상자 — 아이템 뽑기 설계

박사 포인트로 도는 아이템 뽑기. 하루 첫 판은 무료이고, 그다음부터 그날 안에서 값이 두 배씩
오른다. 나오는 것은 소모품과 알 확정권이며, 결과는 등급 연출로 열린다.

## 왜 만드나

박사 포인트의 소비처가 **제안 데려오기 하나뿐**이다. 레전더리 제안이 200점이라 목표로는
충분하지만, 그 사이 며칠 동안 포인트는 아무 데도 안 쓰인다. 매일 한 번 열리는 자리를 만들어
포인트가 쌓이기만 하는 구간을 없앤다.

## 측정한 경제 (설계의 바닥)

| 값 | 실측 |
|---|---|
| 의뢰 3개 완수 | **30점/일** (5 + 10 + 15, `DailyQuest.points`) |
| 개체 방출 | `ReleaseBalance.base(grade) × (진화단계 + 1 + 레벨/100)` — 안 키운 커먼 **2점**, 레전더리 최종형 **160점** |
| 현실적 벌이 | **하루 30~70점** |
| 유일한 소비처 | 제안 데려오기 — 커먼 10 / 레어 25 / 에픽 60 / 레전더리 200 (`ProfessorBalance.price`) |
| 알 뽑기 값 | 10,000,000 토큰 (`EggBalance.drawPrice`) |
| 알 등급 확률 | 커먼 600 / 레어 220 / 에픽 160 / 레전더리 20 (천분율, `EggBalance.odds`) |
| 친밀도 | `bondDuration` = 곁에 둔 시간 + 쓰다듬은 시간. 쓰다듬기는 **1초 = 180초**(`Petting.secondsPerSecondHeld`) |
| 친밀도 진화 문턱 | 86,400초 (`EvoRequirement.friendshipSeconds` = `Ribbon.bond.requiredPartnerSeconds`) |
| 사탕 하나 | 상점 500,000,000 토큰 = 경험치 1억 |

### 값을 고정하면 경제가 뚫린다

포인트는 개체 방출로 번다. 알 하나가 1천만 토큰이고 거기서 나온 안 키운 커먼이 2점이므로
**1천만 토큰 ≈ 2~3점**이다. 뽑기 값이 20점으로 고정이면 한 판의 입력이 약 8천만 토큰인데,
아래 풀의 기대값은 그보다 크다. 부화 시간이 제동을 걸긴 하지만 3슬롯 × 30분이면 하루
100~150점이 나와 **하루 7판까지 도는 순환**이 생긴다.

그래서 값을 **그날 안에서 두 배씩** 올린다. 무료 → 20 → 40 → 80 → 160… 이면 하루 150점을
버는 사람도 무료 포함 4판에서 멈춘다(20+40+80 = 140). 제안(레전더리 200)이 포인트의 큰
목적으로 남고 뽑기가 그것을 밀어내지 않는다.

## 나오는 것과 확률

`EggBalance.odds` 와 같은 **정수 천분율**로 선언한다. 소수 확률을 누적 차감하면 이진 소수에서
딱 안 떨어져 마지막 항목이 새는데, 그 이유와 해법(굴림을 천분율 정수 공간으로 스케일링)이
`EggBalance.grade(for:)` 에 이미 적혀 있다. 같은 방식을 쓴다.

| 상품 | 가중(‰) | 연출 등급 | 자리의 근거 |
|---|---|---|---|
| 경험치 사탕 ×1 | 340 | common | 바닥. 일일 보너스가 이미 매일 하나 주므로 이것이 "꽝"의 기준선이다 |
| 마사지 쿠폰 ×1 | 300 | common | 친밀도 24시간 = 쓰다듬기 8분. 공짜로 얻을 수 있는 것의 단축이라 흔해도 된다 |
| 세대 알 확정권 ×1 | 180 | rare | 세대는 뽑을 때 1~9 에서 균등하게 굴린다 |
| 레어 알 확정권 ×1 | 120 | rare | |
| 에픽 알 확정권 ×1 | 45 | epic | |
| 레전더리 알 확정권 ×1 | 15 | legendary | 최상급. 알 뽑기 50판어치(≈5억 토큰) |

합 **1000‰**. 한 판의 토큰 환산 기대값 ≈ **1.9억** — 일일 보너스(사탕 1개 = 5억)보다 작아
기존 보상을 덮지 않는다.

### 반짝이는 사탕은 넣지 않는다

CLAUDE.md 가 아니라 `DexMissions.all` 의 주석에 사용자 결정이 기록돼 있다 — 반짝사탕은
**게임 전체를 통틀어 2개**(도감 400종·800종)이고, 그 전에 15개를 뿌리던 판을 "너무 많이 주는
것 같다"는 지적으로 걷어냈다. 매일 도는 뽑기에 넣으면 그 결정이 무효가 된다. 총량을 잠그는
테스트가 이미 있으므로, 이 풀에 넣으면 그 테스트가 깨지는 것이 정상이다.

## 값 사다리

`CharmLadder` 안에 두 배 사다리 계산이 박혀 있다 — `price(tier:)`, `cumulative(through:)`,
`maxSafeTier`, `pow2`. **공유 타입이 따로 있지 않다.** 이것을 `DoublingLadder` 로 빼내
`CharmLadder` 와 아이템 뽑기가 같이 쓴다.

```swift
/// base 로 시작해 단계마다 두 배가 되는 값 사다리. 상한은 base 에서 유도한다 —
/// 손으로 적은 상한을 실제로 밟아 `Int` 곱셈 트랩으로 프로세스가 죽은 전례가 있다.
struct DoublingLadder {
    let base: Int
    let maxStep: Int

    init(base: Int) {
        self.base = base
        var step = 1
        while Int.max / base >= (1 << (step + 1)) - 1 { step += 1 }
        self.maxStep = step
    }

    /// 이 단계의 값. 1단계 미만이거나 상한을 넘으면 값이 없다.
    func price(step: Int) -> Int? {
        guard step >= 1, step <= maxStep else { return nil }
        return base * (1 << (step - 1))
    }

    /// 여기까지 오는 데 든 총액.
    func cumulative(through step: Int) -> Int {
        guard step >= 1 else { return 0 }
        return base * ((1 << min(step, maxStep)) - 1)
    }
}
```

`CharmLadder` 는 `static let ladder = DoublingLadder(base: basePrice)` 를 들고 기존
`price(tier:)`·`cumulative(through:)`·`maxSafeTier` 를 그 위로 위임한다. 외부 시그니처는
그대로 두므로 호출부와 기존 테스트가 안 바뀐다 — 그 테스트들이 곧 추출의 회귀 가드다.

아이템 뽑기는 `ItemDrawBalance.ladder = DoublingLadder(base: 20)` 을 쓴다. 오늘 유료로 n 번
뽑았으면 다음 값은 `ladder.price(step: n + 1)`.

## 상태와 하루 경계

`PlayerState` 에 두 개를 더한다.

```swift
/// 오늘 무료 한 판을 썼나.
var freeItemDrawUsed = false
/// 오늘 유료로 몇 판 뽑았나 — 다음 값이 이 수에서 나온다.
var paidItemDraws = 0
```

초기화는 **이미 하루가 바뀌는 것을 판정하는 그 한 곳**에 붙인다 — `PlayerStore.swift` 의
`todayDate != state.lastDate` 블록(지금 `claimedTodayTokens`·`dailyCounts`·`claimedDailyQuests`
를 비우는 자리). 하루 판정이 두 곳에 있으면 반드시 갈린다는 것이 그 블록의 주석이 말하는
내용이고, 같은 성격의 로컬 장부이므로 같은 자리에 둔다.

`paidItemDraws` 는 경계에서 잘라 담는다 — `PlayerState.init(from:)` 이 부르는 `sanitized()`
계열과 같은 이유다. 봉인이 깨진 세이브의 큰 값이 `1 << (n-1)` 에 들어가면 오버플로 트랩으로
프로세스가 죽는다. 범위는 `[0, ladder.maxStep]`.

## 새 아이템 둘

### 마사지 쿠폰

`ShopItem` 에 소모품 한 개를 더한다(`massageCoupon`). 상점에서는 **안 판다** —
`tokenPrice` 는 `Int.max`, `isPurchasable` 은 false 로 두어 알 확정권·무지개 부적과 같은
"뽑기·미션으로만 들어오는 것" 자리에 놓는다.

쓰는 자리는 **개체 상세 화면**이다. 이 저장소의 규칙이 "모든 아이템은 그 포켓몬의 자기
화면에서 쓴다"이고, 가방은 보기만 하는 곳이다. 효과는 그 개체의 `pettedSeconds += 86_400`.

`partnerSeconds` 가 아니라 `pettedSeconds` 인 이유는 이미 기록돼 있다 — `partnerSeconds` 에
더하면 화면의 "함께한 시간"까지 늘어 실제로 곁에 있던 시간을 거짓으로 말하게 된다(사용자
지적). 문턱 판정만 `bondDuration` 이 둘을 합쳐 본다.

한 장이 친밀도 진화 문턱(86,400초)을 정확히 한 번에 넘긴다는 것을 알고 값을 매겼다. 다만
쓰다듬기로 8분이면 같은 양을 얻으므로 새로운 능력이 아니라 단축이다.

### 세대 알 확정권 ×9

`ShopItem` 에 `gen1EggTicket` … `gen9EggTicket` 아홉 개를 더한다. 등급 확정권이
`guaranteedGrade` 를 갖는 것과 나란히 `guaranteedGeneration: Int?` 를 갖는다.

개봉은 기존 확정권과 **같은 경로**를 쓴다. `EggBalance.pickSpecies(from:grade:roll:unseenIn:)`
가 종 선택의 유일한 관문이므로(상점 뽑기·확정권·박사의 제안이 전부 여기를 지난다), 넘기는
인덱스를 `DexMissions.generations[n]` 범위로 거르면 그 세대만 나온다. 등급은 평소 확률로
굴린다 — 세대만 한정하는 쿠폰이라는 뜻 그대로이고, 2% 로 그 세대의 전설까지 나온다.

**함정 하나를 피해야 한다.** `pickSpecies` 의 주석이 경고하듯, 인덱스를 미리 걸러 넘기면 어떤
등급의 후보가 비었을 때 등급 걷기가 아래로 내려가 **굴려 놓은 등급이 바뀐다.** 세대마다
전설이 있으므로 실사용에서는 안 비지만, 인덱스가 부분적으로만 받아진 상태에서는 빌 수 있다.
따라서 **등급을 먼저 굴리고, 그 등급에 이 세대 후보가 없으면 세대 제한을 유지한 채 등급을
내린다** — 즉 지금의 걷기 규칙을 세대로 거른 인덱스 위에서 그대로 돌린다. `pickSpecies` 는
이미 그렇게 동작하므로 **거른 인덱스를 넘기는 것만으로 충분하다.** 테스트가 이 성질을
잠근다(거른 인덱스로 부른 결과가 항상 그 세대 범위 안).

## 뽑기 자체

```swift
enum ItemDrawBalance {
    static let ladder = DoublingLadder(base: 20)

    /// 상품 하나. `weight` 는 정수 천분율이고 이것이 유일한 선언이다.
    struct Entry {
        let prize: ItemPrize
        let weight: Int
        /// 연출 단계 — 알 뽑기와 같은 사다리를 쓴다.
        let rarity: Grade
    }

    static let pool: [Entry] = [
        Entry(prize: .item(.expCandy, 1),           weight: 340, rarity: .common),
        Entry(prize: .item(.massageCoupon, 1),      weight: 300, rarity: .common),
        Entry(prize: .generationTicket,             weight: 180, rarity: .rare),
        Entry(prize: .item(.rareEggTicket, 1),      weight: 120, rarity: .rare),
        Entry(prize: .item(.epicEggTicket, 1),      weight:  45, rarity: .epic),
        Entry(prize: .item(.legendaryEggTicket, 1), weight:  15, rarity: .legendary),
    ]
}

enum ItemPrize: Equatable {
    case item(ShopItem, Int)
    /// 세대는 뽑는 순간 1…9 에서 굴린다 — 상품 표에 아홉 줄을 세우지 않는다.
    case generationTicket
}
```

굴림은 `EggBalance.grade(for:)` 와 같은 정수 공간 누적 차감이다.

`PlayerStore` 에 `drawItem()` 을 더한다. 순서와 실패 규칙은 `acceptProfessorOffer` 를 따른다:

1. 무료가 남았으면 무료로 뽑고 `freeItemDrawUsed = true`.
2. 아니면 `ladder.price(step: paidItemDraws + 1)` 을 구한다. 값이 없거나(상한) 포인트가
   모자라면 **nil 을 돌려주고 아무것도 차감하지 않는다.**
3. 굴려서 상품을 정하고, 차감·지급·카운터 증가를 **한 번의 `mutate`** 안에서 한다. 갈라 두면
   "포인트는 줄었는데 물건이 없다"가 생긴다(`redeemEggTicket` 이 같은 이유로 한 함수다).

지급은 `PlayerStore.grant(_:into:)` 를 쓴다 — 미션과 컬렉션이 이미 공유하는 지급 경로이고,
갈라 두면 한쪽만 고쳐지는 부류가 난다.

## 연출

알 뽑기 연출(`EggRevealView`)과 **같은 무대**를 쓴다. 배경·링·파티클·단계 진행(`RevealMotion`,
`EggReveal.stages(for:)`)은 등급만 받으면 되는 부분이고, 다른 것은 가운데에 서는 그림과 결과
줄뿐이다.

`EggRevealView` 에서 그 공통부를 `RevealTheater` 로 빼내 가운데 그림과 결과 줄을 주입받게
한다. **`RevealStage` 라는 이름은 못 쓴다** — 이미 `EggReveal.stages(for:)` 가 돌려주는 한
단계를 가리키는 타입이고, 같은 이름을 무대 전체에도 붙이면 둘이 섞인다.
알 연출은 알 그림 + 이로치 반짝임을 넣고, 아이템 연출은 아래 그림 + 아이템 이름을 넣는다.

**배경은 이미 불투명해야 한다** — 반투명 배경이 뒤의 부화칸 줄을 비춰 결과를 미리 알려준
전례가 있고(1.16.2), `DrawRevealCoverTests` 가 두 배경 위에 그린 두 장이 같은지로 그것을
잠그고 있다. 공통부를 빼낼 때 그 테스트가 계속 통과해야 하며, 아이템 연출에도 같은 테스트를
하나 더 둔다.

가운데 그림:

| 상품 | 그림 |
|---|---|
| 경험치 사탕 | SF Symbol `pills.fill` |
| 마사지 쿠폰 | SF Symbol `hands.sparkles.fill` |
| 등급 알 확정권 | `EggIcon(grade:)` — 그 등급의 실제 알 그림(이미 있다) |
| 세대 알 확정권 | 등급 없는 알 실루엣(뽑기 칸이 쓰는 템플릿 렌더링) + 세대 숫자 |

두 심볼은 SF Symbols 1.0/2.0 세대라 macOS 14 바닥에서도 있다. 그래도 **API 에 직접 물어보는**
테스트를 둔다(`NSImage(systemSymbolName:)` 가 nil 이 아닌지) — 픽스처가 아니라 그 API 에
물어보는 방식은 이 저장소가 특이행렬 사건에서 택한 것과 같다.

## 자리

박사 구역의 세 번째 칸 — 제안(`ProfessorOfferSection`) → 의뢰(`DailyGoalsView`) → 상자.
이름은 **박사의 상자 / Professor's Box / はかせのはこ**.

한 줄에 지금 포인트, 다음 값(또는 "오늘 무료 한 판"), 뽑기 버튼이 선다. 값이 모자라면 버튼이
흐려지고, **왜 못 누르는지 줄 아래가 말한다** — 회색 버튼만 두고 이유를 안 적어 사용자가
물어볼 곳이 없던 전례가 바로 직전 릴리스에 있다.

## 테스트

- **확률 표**: 가중 합이 정확히 1000. 모든 가중 > 0. `[0,1)` 을 촘촘히 훑어 여섯 상품이 전부
  실제로 나온다(정수 공간 누적 차감이 마지막 항목을 안 흘리는지).
- **반짝사탕 부재**: 풀에 `shinyCandy` 가 없다. 기록된 결정을 잠근다.
- **사다리**: 20 / 40 / 80 / 160 순서. 상한을 넘는 단계는 nil. `base` 를 바꾸면 상한도 따라
  움직인다(손으로 적은 상한을 밟은 전례의 가드).
- **추출 회귀**: `CharmLadder` 의 기존 가격·누적·상한 테스트가 그대로 통과한다.
- **하루 경계**: 무료는 하루 한 번. 날짜가 바뀌면 무료와 유료 카운터가 **둘 다** 초기화된다.
  초기화가 그 한 곳에서 일어나는지 소스로 확인한다(마이그레이션을 뷰에 매달아 영영 안 돌던
  전례와 같은 부류라, 호출 존재를 소스에서 본다 — **주석을 걷어낸 뒤에** 찾는다).
- **차감 없는 실패**: 포인트가 모자라면 nil 이고 포인트가 그대로다. 상한을 넘은 단계도 같다.
- **세대권**: 걸러 넘긴 인덱스로 뽑은 종이 항상 그 세대 범위 안. 아홉 세대 모두 도달 가능.
  대조군으로, 안 거른 인덱스는 범위 밖도 낸다(거르기가 실제로 일하는지).
- **마사지 쿠폰**: 쓴 개체의 `pettedSeconds` 만 86,400 늘고 다른 개체는 안 변한다. 쓰기 전에는
  친밀도 진화가 안 되고 쓴 뒤에는 된다(문턱을 실제로 넘는지). 쿠폰이 없으면 실패하고 개체도
  안 변한다.
- **연출**: 아이템 연출도 뒤가 안 비친다 — 서로 다른 두 배경 위에 그린 두 장이 같은 픽셀.
- **심볼 존재**: 쓰는 SF Symbol 이 실제로 만들어진다.
- **경계 검증**: 봉인이 깨진 세이브의 `paidItemDraws` 가 `[0, maxStep]` 으로 잘린다.

## 안 하는 것

- **천장(피티)** — 하루 1회 무료를 도는 사람에게는 몇 주가 걸려 체감이 없다.
- **중복 보호** — 상품이 전부 소모품이라 중복이 손해가 아니다.
- **상점 판매** — 마사지 쿠폰과 세대권은 뽑기·미션으로만 들어온다. 상점에 놓으면 이 뽑기를
  돌 이유가 사라진다.
- **10연차** — 값이 그날 안에서 두 배씩 오르는 구조와 안 맞는다.
