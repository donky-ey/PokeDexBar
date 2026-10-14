# 진화 조건·결과가 **무엇에 따라** 갈리는가 (설계)

2026-10-14 · 사용자 제보("마빌크 진화 도구가 잘못된 것 같다")에서 출발해 전수 조사로 범위가 드러난 건.
PokéAPI 전 540체인 484간선 전수 확인(2026-10-12)에 근거한다.

## 왜

이 앱의 진화 조건은 **갈래마다 하나**다 — `EvoRequirement.item(EvolutionItem)` 하나, 그리고 지방
모습용 예외 하나(`regionalRequirementRaw`). 그런데 원작에는 조건과 결과가 **다른 축으로 갈리는**
갈래가 넷 있고, 넷 다 지금 틀려 있다.

실응답 4체인을 앱 파서(`PokeAPIClient.node(from:)`)에 통과시킨 결과:

```
854  → 855   item("cracked-pot")          진작 데인차도 깨진포트를 요구 (원작은 이빠진포트)
1012 → 1013  item("unremarkable-teacup")  명품 차데스도 범작찻잔을 요구 (원작은 명품찻잔)
891  → 892   item("scroll-of-darkness")   물의족자가 무의미하고 연격 우라오스가 없다
868  → 869   level(20)                    도구를 아예 안 요구한다 (원작은 사탕공예를 들고 회전)
```

게다가 `ForageCatalog` 는 앞의 셋에 **도구를 둘 다** 물어오게 해 두었다. 지금은 쓸모없는 쪽을
며칠 걸려 모으게 하고, 정작 요구는 엉뚱한 쪽으로 한다.

## 부류가 둘이다 — `required_pokemon_form` 이 가른다

조사 중 두 번 틀렸고, 둘 다 이 필드를 안 보고 뭉뚱그린 탓이었다. 기록해 둔다.

### 규칙 ② — 태생 모습이 **요구 도구**를 가른다 (`required_pokemon_form` 있음)

모습은 얻을 때 이미 정해져 있고, 도구는 고르는 게 아니라 **짝이 맞아야** 한다.

| 간선 | 태생 모습 | 맞는 도구 | 결과 |
|---|---|---|---|
| 854 → 855 | 위작(기본) | 깨진포트 | `polteageist` |
| 854 → 855 | 진작(`antique`) | 이빠진포트 | `polteageist-antique` |
| 1012 → 1013 | 범작(기본) | 범작찻잔 | `sinistcha` |
| 1012 → 1013 | 명품(`artisan`) | 명품찻잔 | `sinistcha-masterpiece` |

**모습 자체는 이미 구현돼 있다** — `BirthFormCatalog` 의 `sinisteaLine`·`poltchageistLine` 이 진화
단계 슬러그까지 들고 있고, `BirthFormBalance` 가 부화 때 굴린다. **요구 도구만 안 갈린다.**

이것은 CLAUDE.md 의 *"여러 조건줄을 우선순위로 접을 때, 그 줄들이 서로 다른 대상의 것일 수 있다"*
와 **같은 필드를 읽는 같은 결함**이다(기본 야도란이 가라두구팔찌를 요구한 그 건). 축이 지방이
아니라 태생 모습이라 `PokeAPIClient.isRegional`(지방 접미사 검사)이 안 잡을 뿐이다.

### 규칙 ① — 쓴 도구가 **결과 모습**을 정한다 (`required_pokemon_form` 없음)

전수 확인 결과 **정확히 두 간선**이다.

| 간선 | 도구 → 결과 | 관계 |
|---|---|---|
| 891 → 892 | 어둠의족자 → 일격(`urshifu`), 물의족자 → 연격(`urshifu-rapidstrike`) | **1:1** — 원작 그대로 |
| 868 → 869 | 사탕공예 7종 → 장식 7종 | **1:9** — 각 사탕공예가 크림 9종 전부와 짝지어진다 |

## 마휘핑은 예외다 — 명시적으로 어긋난다

원작 마휘핑의 겉모습은 **독립된 두 축**이다.

| 축 | 원작에서 정해지는 방식 | 앱의 대응물 | Showdown 스프라이트 |
|---|---|---|---|
| 사탕공예 7종 (위 장식) | 진화 시 들고 있던 도구 | 있음 — 도구 체계 | **없음** (`alcremie-strawberrysweet` 등 전부 404, 데이터에도 없음) |
| 크림 9종 (몸 색) | 회전 방향·시간·시각 | **없음** | 있음 (기본 + 8종) |

**메커니즘이 옮겨지는 축에는 그림이 없고, 그림이 있는 축에는 메커니즘이 없다.** 어느 쪽도 온전히
옮길 수 없으므로, 사탕공예(메커니즘)에 크림(그림)을 붙인다. 사용자 결정이다 — "플레이어가 자기
마휘핑의 모습을 고른다"는 성질을 지키는 쪽을 택했다(원작도 회전으로 *고른다*).

이 어긋남은 `EvolvedFormCatalog` 주석에 근거와 함께 남긴다. 숨기면 다음 사람이 "버그"로 보고
원작 쪽으로 되돌리려다 스프라이트가 없다는 벽에 다시 부딪힌다.

## 설계

### 1. `EvoRequirement.item` 이 도구 **집합**을 든다

```swift
case item([EvolutionItem])   // 이 중 하나
```

새 케이스를 더하지 않는다: 하나냐 여럿이냐는 데이터의 우연이지 의미 차이가 아니고, 케이스를
가르면 모든 `switch` 가 도구 모양 분기를 둘씩 영구히 갖는다. `EvoRequirementRaw.item` 도 `[String]`.

- `meetsRequirement` → `items.contains { count(of: $0) > 0 }`
- `shortNeed`(접힌 줄) → 2개면 `"A / B"`, 3개 이상이면 `"A 등 N종"`. 한 줄에 들어가야 한다.
- `blockedHints` → 지금 규칙 그대로(도구 종류가 하나라도 있으면 `evolutionLockedHint` 한 줄).

**세이브 영향 없음** — `EvoNode` 는 `Codable` 이지만 `PokeAPIClient.lineCache` 의 메모리 캐시로만
쓰이고 디스크에 안 간다(확인함).

### 2. 조건을 **태생 모습별로** 담는다

```swift
struct EvoNode {
    var requirementRaw: EvoRequirementRaw              // 기본(원종)
    var regionalRequirementRaw: EvoRequirementRaw?     // 지방 — 그대로 둔다
    var formRequirementsRaw: [String: EvoRequirementRaw] = [:]   // 태생 모습 변종 키별
}
```

파서는 `required_pokemon_form` 이 **지방 접미사가 아닌** 줄에서 종 이름 접두를 뗀 나머지를 변종
키로 본다(`sinistea-antique` → `antique`). 그다음 **그 키가 `BirthFormCatalog` 에 있느냐로 갈린다**:

- **있으면** 그 모습 전용 조건 → `formRequirementsRaw[key]`.
- **없으면 기본형 줄**이다 → 지금처럼 `requirementRaw` 로 간다. 기본형은 카탈로그 항목이 아니라
  *항목 없음*으로 표현되기 때문이다(CLAUDE.md 의 "후보 없음이 곧 기본형").

실제로 이 규칙이 네 줄을 정확히 가른다: `sinistea-phony`·`poltchageist-counterfeit` 는 카탈로그에
없으므로 기본 조건(깨진포트·범작찻잔)이 되고, `sinistea-antique`·`poltchageist-artisan` 은 있으므로
맵으로 간다(이빠진포트·명품찻잔). 이브이 19줄처럼 지방과도 태생 모습과도 무관한 값은 같은 규칙에
의해 자동으로 기본 조건에 흡수된다 — **값의 유무로 가르지 않는다**(그렇게 갈랐다가 이브이의 조건을
통째로 날릴 뻔한 적이 있다).

조회:

```swift
func requirement(for speciesID: Int, line: EvoLine, region: Region?, birthForm: String?) -> EvoRequirement
```

우선순위 **태생 모습 → 지방 → 기본**. 지방 경로는 **이번에 안 건드린다**(이미 돌아가고, 두 번
틀렸던 자리라 회귀 위험이 크다).

### 3. 쓴 도구를 받아 결과 모습을 박는다

```swift
func evolve(individualID: UUID, to speciesID: Int, line: EvoLine, using item: EvolutionItem? = nil) -> Bool
```

- `using` 이 nil 이면 **요구 집합이 1개일 때만** 허용한다. 여럿인데 생략하면 실패다 — 호출부가
  조용히 첫 번째를 쓰면 플레이어의 선택이 사라진다(이 세션에서 "첫 번째를 쓰면 줄 순서에 기대는
  것"에 이미 한 번 데었다).
- `EvolvedFormCatalog.variant(speciesID:item:)` 이 값을 주면 개체에 박는다.

### 4. 박힌 모습은 `Individual.birthForm` 에 산다

성질이 정확히 같다: **키로 저장**(슬러그가 아니라 — 단계마다 슬러그가 다르다), 평생 고정, 진화해도
이어짐, 도구로 안 바뀜. `spriteForm`·`DexKey`·배지 라벨이 이미 그 경로를 갖고 있어 **새 필드를
만들면 그 세 자리에 같은 분기가 하나씩 더 생긴다.**

- 속성명을 **`fixedForm`** 으로 바꾼다. 지금 이름·주석이 "부화할 때"라 ①에 쓰면 거짓이 된다.
- **저장 키(`birthForm`)는 유지한다.** 원칙 2는 쓰이지 않는 *코드 경로*를 지우라는 것이지 사용자
  파일을 깨라는 것이 아니다. `CodingKeys` 에 한 줄 남기는 것이 전부다.
- 주석: "정해지면 평생 안 바뀌는 변종 키 — 대개 부화 때(`BirthFormCatalog`), 둘은 진화 때
  (`EvolvedFormCatalog`)."

### 5. `FixedForm.resolve(speciesID:variant:)` 한 자리

두 카탈로그를 순서대로 묻는다(`BirthFormCatalog` → `EvolvedFormCatalog`). `spriteForm`·`DexKey`·
라벨 **세 곳이 그 한 함수를 쓴다** — 지금 세 곳이 각각 `BirthFormCatalog` 를 직접 부르고 있어
그대로 두면 분기가 세 번 늘어난다.

### 6. `EvolvedFormCatalog`

(종, 도구) → 변종 키 · 슬러그 · 라벨. **기본형 쪽은 키를 안 박는다** — "후보 없음이 곧
기본형"(CLAUDE.md)이고, 그래야 도감 키가 `892`/`892-urshifu-rapidstrike` 로 자연스럽게 갈린다.

| 종 | 도구 | 변종 키 | 슬러그 | 라벨(공식) |
|---|---|---|---|---|
| 892 | 어둠의족자 | — | `urshifu` | (기본) |
| 892 | 물의족자 | `rapidstrike` | `urshifu-rapidstrike` | 연격의 태세 |
| 869 | 딸기사탕공예 | — | `alcremie` | (기본 — 기본 스프라이트가 바닐라+딸기다) |
| 869 | 베리사탕공예 | `rubycream` | `alcremie-rubycream` | 루비크림 |
| 869 | 하트사탕공예 | `matchacream` | `alcremie-matchacream` | 말차크림 |
| 869 | 스타사탕공예 | `mintcream` | `alcremie-mintcream` | 민트크림 |
| 869 | 네잎사탕공예 | `lemoncream` | `alcremie-lemoncream` | 레몬크림 |
| 869 | 꽃사탕공예 | `saltedcream` | `alcremie-saltedcream` | 솔트크림 |
| 869 | 리본사탕공예 | `rainbowswirl` | `alcremie-rainbowswirl` | 레인보우스월 |

슬러그 10종 전부 `gen5`·`ani` 양쪽 200 확인(2026-10-12). 남는 크림은 루비스월·캐러멜스월이다.
**사탕공예↔크림 대응에는 정답이 없다**(원작에서 둘은 독립 축이다) — 리뷰에서 바꿔도 된다.

라벨은 **공식 이름표에서 받는다**(`pokemon-form` 의 `form_names`). 이번 세션에서 도구 이름 109개
중 87개가 기억으로 적혀 틀려 있었다 — 같은 실수를 반복하지 않도록 `scripts/generate-item-names.py`
에 폼 이름도 태워 `ItemNameTests` 와 같은 방식으로 잠근다. 한국어가 없는 항목(`polteageist-antique`)
은 기존 관례대로 일본어 원문에서 옮기고 그 사실을 주석에 남긴다.

### 7. `EvolutionItem` · `ForageCatalog`

- 사탕공예 7종 추가(공식 이름: 딸기/베리/하트/스타/네잎/꽃/리본사탕공예).
- `ForageCatalog[868]` = 사탕공예 7종. **7종 전부 넣는 것이 안전장치다**: 파서가 응답의 첫
  사탕공예를 집합의 머리로 쓰므로 줄 순서가 바뀌어도 막히지 않는다.
- `Need` 에 태생 모습 축을 더한다 — `RegionScope` 와 같은 모양의 `FormScope { any, only(String?) }`
  (`.only(nil)` = 기본형). 854 위작은 깨진포트만, 진작은 이빠진포트만 물어온다. 1012 도 같다.
  891 은 족자 2종 모두 `.any` 로 그대로 둔다(둘 다 유효한 선택지다).
- `UnstatedEvolutionCatalog` 의 `869: .level(20)` 을 **지운다** — 도구가 먼저 걸려 도달 불가가 된다.

### 8. 도감

`892-urshifu-rapidstrike` 와 마휘핑 크림 6개가 도감 칸으로 늘어난다(안농 26글자·비비용 18무늬와
같은 취급). 영구 고정이므로 다 모으려면 치고마 2마리·마빌크 7마리가 필요하다 — 원작의 수집 목표를
옮기는 것이라 의도된 비용이다.

## 테스트

픽스처는 **실응답에서 잘라 온다**(손으로 쓰지 않는다 — 픽스처가 파서와 같은 오해를 공유하면 둘 다
틀린 채로 통과한다). 체인 449(데인차)·539(차데스)·470(치고마)·452(마빌크).

| 무엇 | 왜 |
|---|---|
| 854 위작은 깨진포트, 진작은 이빠진포트를 요구 | ②의 트리거 브랜치. 지금은 둘 다 깨진포트다 |
| 1012 범작/명품도 같은 방식 | 같은 부류 둘째 |
| **대조군**: 지방 분기(모래두지·나옹)가 그대로 | ②가 지방 경로를 안 깨뜨렸는지 |
| 891 요구가 `.item([족자 2종])` | ①의 집합 |
| 868 요구가 `.item([사탕공예 7종])` | 지금은 `.level(20)` 이라 **현재 깨짐** |
| **대조군**: 도구 하나인 종이 `.item([1종])` | 집합화가 단일 경로를 안 바꿨는지 |
| `using` 없이 집합 진화를 부르면 실패 | 선택이 조용히 사라지는 것 방지 |
| `using` 로 박힌 모습이 `revertForm` 으로 안 풀림 | 폼이 아니라 고정 변종이라는 성질 |
| `FixedForm.resolve` 가 두 카탈로그를 다 봄 + 변종 키가 안 겹침 | 두 표를 합치는 자리의 유일한 위험 |
| 도감 키가 갈림(일격/연격, 크림별) | 변종이 칸을 늘리는지 |
| 새 슬러그가 그 종의 것인지 | 기존 `testEverySlugBelongsToItsSpecies` 확장 |
| **부류 가드**: "도구가 `evolved_pokemon_form` 을 가르는 간선"과 "`required_pokemon_form` 이 있는 간선"의 전수 집합을 픽스처로 고정 | 데이터가 늘면 카탈로그 누락을 알려 준다. 지금은 각각 2건 — **0이 아닌 것을 확인했다**(장식이 아니다) |

## 안 하는 것

- **지방 조건 경로 리팩터.** `formRequirementsRaw` 가 `regionalRequirementRaw` 의 일반화이긴 하지만
  흡수하지 않는다 — 돌아가고 있고, 두 번 틀렸던 자리다.
- **크림 축(회전) 모델링.** 대응물이 없다.
- **63조합.** 장식 스프라이트가 없으므로 사탕공예별 그림은 만들 수 없다.
- **마휘핑 거다이맥스.** 이미 `alcremie-gmax` 로 있고 이 건과 무관하다.
- **②의 태생 모습 추가.** 이미 있다.

## 구현 순서

1. **②(결함 수정)** — `formRequirementsRaw` + 조회 축 + `ForageCatalog` 의 `FormScope`. 도감은
   안 늘고, 화면에 바뀌는 것은 진작 데인차·명품 차데스 상세의 **요구 도구 이름 한 줄**뿐이라
   스크린샷에 안 담긴다(캡처 대상에 그 둘이 없다). `requirement(for:...)` 시그니처가 바뀌어
   `Sources/**/UI/` 의 호출부를 건드리지만, `fix:` 커밋이라 `release.sh` 의 신규 에셋 하드 게이트
   (`feat:` 한정)에는 안 걸린다. 작고, 틀린 것을 먼저 바로잡는다.
2. **① 기반** — `EvoRequirement.item` 집합화 + `evolve(using:)` + `fixedForm` 개명 +
   `FixedForm.resolve`.
3. **① 적용** — `EvolvedFormCatalog`(치고마 먼저 — 원작 그대로라 판단이 안 필요하다), 그다음
   마휘핑(사탕공예 7종 + 예외 주석).

커밋은 1 / 2+3 으로 가른다 — 1은 결함 수정이고 2+3은 신규 기능이라 성격이 다르다.
①은 `Sources/**/UI/` 를 건드리므로(진화 버튼이 도구별로 갈린다) 릴리스 때 **새 에셋**이 필요하다
(`release.sh` 하드 게이트).
