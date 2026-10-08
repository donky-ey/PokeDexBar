# SP2 Upstream Usage-Display Port Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 업스트림의 사용량 표시 개선 23커밋 + SP1 이월 2건을 포크에 이식한다(가격·비용 → 포맷터 → 표시 모드 → 페이스 → 트렌드 → 리캡 → 잔손질).

**Architecture:** SP1 과 같은 커밋 단위 포팅. 배치 A→G 가 의존 순서다(A 의 `UsageCost` 표현을 E·F 가 쓴다). Core 헝크는 기계 적용 기대, PopoverView 헝크는 전부 수동 각오. 배치 E 에서 SP1 의 포크식 #402 캐리어를 업스트림 `hasDisplayableUsage` 구조로 수렴시키되 SP1 테스트 4개를 회귀 가드로 유지한다.

**Tech Stack:** Swift 6 / SwiftPM, XCTest. 소스는 업스트림 diff — `git show <hash>`.

**Spec:** `docs/superpowers/specs/2026-10-08-sp2-usage-display-port-design.md`

## Global Constraints

- 작업 브랜치: `port/sp2-usage-display` (main 분기, 완료 후 로컬 머지).
- 커밋 영어 + `(upstream #NNN)` 참조, `Co-Authored-By` 금지.
- `Localization` 헝크는 **ko/en/ja 만** — 업스트림 추가 언어(fr/es/de/pt/ru) 값은 버린다.
- 포크에 없는 파일(Aside·Antigravity·Kiro·CursorUsageAPI 등) 헝크·테스트는 전부 버린다.
- UI 설정의 `UserDefaults` 키 이름은 업스트림과 동일하게 유지(이후 포팅 diff 최소화).
- 메뉴바 컴팩트 규율(오늘 사용>0)·idle 규율(setStatusImage 트랜잭션·diff-gate)·키체인 규율과
  충돌하는 헝크는 포크 규율 우선 — 그 헝크는 버리고 장부에 기록.
- 커밋은 `git add -A ':!.superpowers' ':!AGENTS.md'` + 사전 `find . -name '*.rej' -o -name '*.orig'` 청소.
  (SP1 리뷰에서 실제로 밟은 함정 2개의 재발 방지.)
- 전체 스위트는 배치 경계 7곳(각 배치 마지막 태스크 끝)에서.

## 공통 포팅 절차 P (태스크의 "절차 P"는 이것 — 값만 다르다)

```bash
# P1. 커밋 전체 정독 (적용 전 필수)
git show <HASH>
# P2. 테스트 선이식 (경로 치환; 버릴 테스트 파일은 태스크에 명시)
git show <HASH> -- 'Tests/*' | sed 's|PokeTokenBar|PokeDexBar|g' | git apply --reject
# P3. RED — 기능 부재로 실패 확인(컴파일 에러 포함). UI 전용 커밋은 RED 불가 시 태스크에 명시된 대체 검증.
swift test --filter <TESTCLASS> 2>&1 | grep -E "error|failed"
# P4. 소스 적용 → *.rej 는 수동 이식(함수 단위로 자리 찾기), 버릴 헝크는 이식하지 않는다
git show <HASH> -- 'Sources/*' | sed 's|PokeTokenBar|PokeDexBar|g' | git apply --reject
# P5. GREEN
swift test --filter <TESTCLASS>
# P6. 커밋
find . -name '*.rej' -o -name '*.orig' | xargs rm -f
git add -A ':!.superpowers' ':!AGENTS.md' && git commit -m "<MESSAGE>"
```

## Review Focus

1. **#289 폴백 제거 × 포크 전용 모델** — 패밀리 폴백이 사라지면 grok(명시 비용만)·gemini 변형의
   비용이 "불가"로 오표시될 수 있다. → Task 1 Step 3.
2. **잔여 표시 모드 × 메뉴바** — 팝오버는 잔여인데 메뉴바 퍼센트가 사용 기준이면 같은 숫자가
   두 화면에서 반대로 읽힌다. → Task 9 Step 3.
3. **페이스 분모 경계** — 리셋 직후(경과 0)·리셋 지난 창(경과>100%)에서 마커·색 계산이
   0나눗셈/범위 밖으로 새지 않아야 한다. → Task 12 Step 3.
4. **리캡 주 경계 로케일** — 포크의 주 시작(`startOfWeek`)과 리캡의 주 정의가 다르면 주간 리캡
   합계가 팝오버 주간 합계와 어긋난다. → Task 18 Step 3.
5. **스크린샷 생성기 × 새 UI** — 캡처는 그리기 경로라 CALayer 필터 수식어(.brightness 등)가
   빠진다(CLAUDE.md). 새 게이지 색·마커가 렌더 확인에서 안 보이면 수식어부터 의심. → Task 21 Step 2.

---

## 배치 A — 가격·비용 기반

### Task 1: 추정/불가 비용 구분 (`69ff39b`, #289) — SP2 최대 항목

**Files:**
- Create: `Sources/PokeDexBar/Core/UsageCost.swift`, `Sources/PokeDexBar/UI/UsageCostText.swift`(#293 이 다듬음)
- Modify: `Core/ModelPricing.swift`, `Core/Models.swift`, `Core/UsageProvider.swift`, `Core/UsageStore.swift`, `Core/LocalUsageReader.swift`, `Core/LocalUsageCache.swift`, `Core/LocalUsageProvider.swift`, `Core/LocalAdditionalUsageProvider.swift`, `Core/Localization.swift`(ko/en/ja), `UI/PopoverView.swift`(수동 각오)
- Test: 업스트림 13개 테스트 파일 중 포크에 있는 것만(ModelPricingTests·LocalUsageReaderTests·UsageStoreTests·LocalAdditionalUsageTests 등). **버림**: AntigravityUsageTests·AsideUsageTests·KiroUsageTests·CursorUsageTests.

**Interfaces:**
- Produces: `UsageCost`(추정/보고/불가 구분 표현 — 정확 시그니처는 P1 에서 확인해 아래 태스크들이 그대로 씀), `ModelPricing.rate(for:)` 의 옵셔널화(폴백 제거).

- [ ] **Step 1: 절차 P** — HASH=`69ff39b`, TESTCLASS=`ModelPricingTests|LocalUsageReaderTests|UsageStoreTests|LocalAdditionalUsageTests`, MESSAGE=`fix: distinguish estimated and unavailable usage costs (upstream #289)`
- [ ] **Step 2: SP1 이월 흡수.** ① 포크의 `hasIntendedPrice`(수동 복제 목록)를 #289 구조(옵셔널 rate)로 대체 — `noteUnpriced` 호출부도 그 판정을 쓰게. ② `noteUnpriced` 게이트를 `explicitCost<=0` 폴백 경로까지 보게 수정. SP1 테스트(`ModelPricingTests` 2개)는 구조 변경 후에도 **의미 그대로 통과**해야 한다(이름/API 만 조정 허용).
- [ ] **Step 3: 포크 전용 모델 가드 (Review Focus 1).** 폴백 제거 후에도 ① grok 엔트리(명시 비용 보유)가 "보고 비용"으로 ② 명시 비용 없는 grok/gemini-pro 가 업스트림과 같은 분류로 표시되는지 테스트:

```swift
/// #289 는 패밀리 폴백을 걷어낸다 — 포크 전용 흐름(grok 명시 비용)이 "불가"로 강등되면 안 된다.
func testGrokExplicitCostSurvivesTheFallbackRemoval() {
    var bucket = LocalUsageReader.Bucket()
    bucket.add(LocalUsageReader.Entry(id: "g", date: Date(), localDay: "2026-10-08",
                                      model: "grok-4-fast", input: 10, output: 5,
                                      cacheWrite: 0, cacheRead: 0, explicitCost: 0.42))
    XCTAssertEqual(bucket.cost, 0.42, accuracy: 1e-9)
    // 분류 표현(UsageCost)의 정확한 단언은 P1 에서 확인한 실제 API 로 작성한다 —
    // 요구는 고정이다: 명시 비용 = '보고', 표에 있는 모델 = '추정', 둘 다 아님 = '불가'.
}
```
- [ ] **Step 4:** `swift test` 전체 PASS → 커밋.

### Task 2: Claude 5 패밀리 가격 (`1ef1979` #304 + `ad9e75e` #198 차이분)

**Files:** Modify `Core/ModelPricing.swift` / Test `ModelPricingTests.swift`, `LocalUsageReaderTests.swift`

- [ ] **절차 P** — HASH=`1ef1979`, TESTCLASS=`ModelPricingTests|LocalUsageReaderTests`, MESSAGE=`fix: price the Claude 5 family exactly (upstream #304)`
  - SP1 이 fable-5/fable-5-1 두 행을 선반영했다 — 중복 행은 업스트림 값으로 통일하고 리젝트는 수동 정리.
- [ ] **#198 차이분 확인**: `git show ad9e75e` 의 최종 값이 현재 표와 같으면 스킵(장부에 기록), 다르면 그 값으로 갱신 후 같은 테스트로 커밋 — MESSAGE=`fix: price claude-fable-5 from the updated LiteLLM snapshot (upstream #198)`

### Task 3: 가격 행 3건 (`29a4e2d` #309 → `832154a` #354 → `1e5603a` #384)

**Files:** Modify `Core/ModelPricing.swift` / Test `ModelPricingTests.swift`

- [ ] **절차 P ×3 (커밋 3개, 업스트림 순서대로)** — TESTCLASS=`ModelPricingTests`, MESSAGE 각각
  `fix: price gemini-2.5-flash-lite (upstream #309)` / `fix: price Claude Opus 5.5 (upstream #354)` / `fix: price recent frontier models (upstream #384)`

### Task 4: 비용 달러 표기 (`a8b3ba8`, #293) — 배치 A 마감

**Files:** Modify `Core/UsageCost.swift`, `UI/UsageCostText.swift`, `Core/Localization.swift`, `UI/PopoverView.swift` / Test: 업스트림 테스트 1파일

- [ ] **절차 P** — HASH=`a8b3ba8`, TESTCLASS=P1 에서 확인(비용 표기 테스트 파일명), MESSAGE=`fix: display usage costs as plain dollar amounts (upstream #293)`
- [ ] **배치 게이트:** `swift test` 전체 PASS.

---

## 배치 B — 포맷터

### Task 5: 단위 승격 (`4cab9f0`, #365) / Task 6: 정밀도 (`711fca7`, #418) — 배치 B 마감

**Files:** Modify `Core/TokenFormatter.swift` / Test `TokenFormatterTests.swift`(포크에 없으면 업스트림 것 신설)

- [ ] **절차 P ×2 (순서 고정 #365→#418, 커밋 분리)** — TESTCLASS=`TokenFormatterTests`, MESSAGE
  `fix: promote compact token units at rounding boundaries (upstream #365)` / `fix: pick formatter precision from the rounded value (upstream #418)`
- [ ] **배치 게이트:** `swift test` 전체 PASS.

---

## 배치 C — 표시 모드·경계

### Task 7: 사용/잔여 표시 모드 (`a1f736e`, #150)

**Files:** Modify `Core/UsageStore.swift`, `Core/Localization.swift`, `UI/PopoverView.swift`, `UI/SettingsView.swift`, `UI/FloatingPetPanel.swift`(포크 펫 코드와 대조해 수동) / Test: 업스트림 2파일 중 포크 보유분

**Interfaces:** Produces: 표시 모드 상태(UserDefaults 키 업스트림 동일) — Task 8·9·12 가 읽는다. 정확한 프로퍼티명은 P1 에서 확인해 장부에 적는다.

- [ ] **절차 P** — HASH=`a1f736e`, TESTCLASS=`UsageStoreTests`, MESSAGE=`feat: add a setting to show limit percentages as used or remaining (upstream #150)`

### Task 8: 그래프 채움 일치 (`fd008e5`, #286)

- [ ] **절차 P** — HASH=`fd008e5`, TESTCLASS=`UsageStoreTests`, MESSAGE=`fix: match quota graph fill to remaining display mode (upstream #286)`

### Task 9: 퍼센트 정렬 (`bb92bd2`, #292) + 메뉴바 일관성 핀

- [ ] **절차 P**(테스트 없음 — P2·P3 생략) — HASH=`bb92bd2`, MESSAGE=`fix: align quota percentages at the trailing edge (upstream #292)`
- [ ] **Step 3 (Review Focus 2):** 잔여 모드에서 `menuLimitLine` 의 숫자가 같은 모드를 따르는지 업스트림 #150 적용 결과를 확인하고, 핀 테스트가 없으면 추가:

```swift
/// 팝오버가 "잔여 19%"를 보여줄 때 메뉴바가 "81%"면 같은 값이 반대로 읽힌다 —
/// 메뉴바 퍼센트도 표시 모드를 따라야 한다(#150 의 의도, 실제 동작은 P1 적용 결과로 확인).
func testMenuLimitLineFollowsTheDisplayMode() { /* 모드 프로퍼티명 확정 후 Task 7 산출 API 로 작성 */ }
```
  (업스트림이 의도적으로 메뉴바를 사용-기준 고정으로 뒀다면 — P1 에서 확인 — 그 동작을 따르고 이 핀은 그 사실을 고정하는 형태로 바꾼다. 어느 쪽이든 테스트는 남긴다.)

### Task 10: 임계 가드 (`231002d`, #410) / Task 11: 절대 리셋 시각 (`f2fe5ac`, #263) — 배치 C 마감

- [ ] **절차 P** — HASH=`231002d`, TESTCLASS=`UsageStoreTests`, MESSAGE=`fix: keep the warning threshold below the critical one (upstream #410)`
- [ ] **절차 P**(테스트 없음 — 포크 자작 1개: 리셋 시각 포맷 순수 함수가 생기면 그 값, 아니면 PopoverView 헬퍼를 nonisolated static 으로 떼어 검증) — HASH=`f2fe5ac`, MESSAGE=`feat: show the absolute reset time next to limit countdowns (upstream #263)`
- [ ] **배치 게이트:** `swift test` 전체 PASS.

---

## 배치 D — 페이스

### Task 12: 페이스 마커 (`2eec9af`, #298)

**Files:** Modify `Core/Models.swift`, `Core/UsageStore.swift`, `Core/Localization.swift`, `UI/PopoverView.swift` / Test: 업스트림 4파일 중 포크 보유분

- [ ] **Step 1–2: 절차 P** — HASH=`2eec9af`, TESTCLASS=`UsageStoreTests`
- [ ] **Step 3 (Review Focus 3):** 업스트림 테스트에 경과 0%·100% 초과 경계가 없으면 추가:

```swift
/// 리셋 직후(경과 0)와 창을 넘긴 시점(>100%)의 마커 — 0나눗셈·범위 밖으로 새면 안 된다.
func testPaceMarkerClampsAtWindowEdges() {
    // P1 에서 확인한 마커 계산 순수 함수에 (elapsed: 0, total: w)·(elapsed: w+1h, total: w)를
    // 넣어 0...1 범위를 단언한다. 함수가 순수가 아니면 떼어낸다(포크 규약: 판정은 순수 함수로).
}
```
- [ ] **커밋** — MESSAGE=`feat: show a pace marker on quota bars (upstream #298)`

### Task 13: 6단계 페이스 색 (`68deb09`, #349)

**Files:** Create `Core/PaceTier.swift` / Modify `UI/PopoverView.swift`, `Core/Localization.swift` / Test: 업스트림 2파일

- [ ] **절차 P** — HASH=`68deb09`, TESTCLASS=`PaceTierTests`(업스트림 파일명 P1 확인), MESSAGE=`feat(popover): color quota bars by pace (upstream #349)`

### Task 14: 메뉴바 퍼센트 색 (`b32717f`, #357) — 배치 D 마감

**Files:** Create `UI/MenuLimitColoring.swift` / Modify `Core/PaceTier.swift`, `Core/UsageStore.swift`, `Core/Localization.swift`, `PokeDexBarApp.swift`(sed 가 `PokeTokenBarApp`→`PokeDexBarApp` 경로까지 치환하는지 확인), `UI/PopoverView.swift`, `UI/SettingsView.swift` / Test: 업스트림 3파일 중 보유분

- [ ] **절차 P** — HASH=`b32717f`, TESTCLASS=`MenuLimitColoring|UsageStoreTests`, MESSAGE=`feat(menubar): color limit percentages like the popover gauges (upstream #357)`
  - **주의(Global Constraints):** 앱 파일 헝크가 `setStatusImage` 트랜잭션/diff-gate 를 건드리면 그 부분은 포크 구현을 유지하고 색 적용만 이식.
- [ ] **배치 게이트:** `swift test` 전체 PASS.

---

## 배치 E — 월간 트렌드 + 캐리어 수렴

### Task 15: 일별 트렌드 (`0912c68`, #270)

**Files:** Modify `Core/LocalUsageProvider.swift`, `Core/LocalAdditionalUsageProvider.swift`, `Core/LocalUsageReader.swift`, `Core/Localization.swift`, `Core/Models.swift`(`monthDaily`), `Core/UsageProvider.swift`, `Core/UsageStore.swift`, `UI/PopoverView.swift` / Test: 업스트림 3파일(`MonthDailyTrendTests` 신설 포함)

**Interfaces:** Produces: `ProviderEnrichment.monthDaily`·`ProviderSnapshot.monthDaily` — Task 16·17·18 전제.

- [ ] **절차 P** — HASH=`0912c68`, TESTCLASS=`MonthDailyTrendTests|UsageStoreTests`, MESSAGE=`feat: show this month's day-by-day usage trend in the popover (upstream #270)`
  - SP1 #402 수렴으로 생긴 포크 고유 캐리어 분기와 겹치는 리젝트 예상 — 이 태스크에선 **포크 분기를 유지**한 채 monthDaily 만 얹고, 교체는 Task 17 에서 한다(한 태스크 한 변경).

### Task 16: 달력 월 배치 (`0269dad` #395) + 프로바이더 스택 (`142fa08` #348)

- [ ] **절차 P ×2 (순서 고정, 커밋 분리)** — 둘 다 PopoverView 전용(수동 각오), TESTCLASS=P1 확인, MESSAGE
  `fix: lay out the daily trend on the calendar month (upstream #395)` / `feat(popover): stack daily trend bars by provider (upstream #348)`

### Task 17: 유휴일 기록 유지 + 캐리어 수렴 (`a8dd806`, #377) — 배치 E 마감

**Files:** Modify `Core/UsageStore.swift`, `UI/PopoverView.swift` / Test `UsageStoreTests.swift`

- [ ] **Step 1: 절차 P1–P5** — HASH=`a8dd806`, TESTCLASS=`UsageStoreTests`
- [ ] **Step 2: 수렴.** SP1 의 포크식 캐리어(phase1 `recentlyUsed` 분기·phase2 `hasActiveBlock || recentlyUsed`)를 업스트림 `hasDisplayableUsage` 구조로 **대체**한다 — `lastUsage` 7일 조건은 `hasDisplayableUsage` 안으로 들어간다(SP1 에서 이미 그 자리에 넣어 둠). **SP1 테스트 4개가 수정 없이 통과해야 한다**: `testRecentUseKeepsTheTabAcrossCalendarResets` · `testUseOlderThanTheWindowStillDropsTheTab` · `testTabsKeepProviderRegistrationOrderWhenACarrierIsAppended` · `testACarrierNeverLeaksIntoTheMenuBar`. 하나라도 깨지면 수렴이 의미를 바꾼 것 — 구현을 고치지 테스트를 고치지 않는다.
- [ ] **Step 3: SP1 이월 정리.** ① phase 2 성공 시 소멸 캐리어 즉시 제거(`snapshots.removeAll { !$0.hasDisplayableUsage }`) + 테스트(enrichment 가 lastUsage nil 을 돌려주면 그 폴에서 탭 소멸). ② 캐리어 도입 전 서술이 남은 주석 2곳 갱신: `PopoverView.swift` "오늘 안 쓴 provider 는 탭/스냅샷이 없어" 부근, `UsageStore.swift` phase2 캐리어 주석. ③ 캐리어 탭 선택 시 오늘 행 부재 — 업스트림 #377 의 PopoverView 헝크가 해결하는지 P1 에서 확인, 안 하면 "오늘 0" 행 표시로 포크에서 보완.
- [ ] **커밋** — MESSAGE=`fix(home): retain historical usage on idle days (upstream #377)` / **배치 게이트:** `swift test` 전체 PASS.

---

## 배치 F — 리캡

### Task 18: 주/월/연 리캡 (`78595ed`, #332)

**Files:** Create `Core/UsageRecap.swift`, `UI/UsageRecapView.swift` / Modify `Core/UsageStore.swift`, `Core/Localization.swift`, `UI/PopoverView.swift`(진입점 — 수동 각오) / Test: 업스트림 1파일(`UsageRecapTests` 류 — P1 확인)

- [ ] **Step 1–2: 절차 P** — HASH=`78595ed`, TESTCLASS=P1 확인, MESSAGE=`feat: add a usage recap for any week, month or year (upstream #332)`
- [ ] **Step 3 (Review Focus 4):** 리캡 주간 합계가 포크 `LocalUsageReader.startOfWeek` 와 같은 주 정의를 쓰는지 — 다르면 팝오버 주간 행과 리캡 주간 합계가 어긋난다. 같은 고정 주(예: 2026-10-05 월요일 시작)로 두 경로를 비교하는 테스트 추가:

```swift
/// 리캡의 '이번 주'와 팝오버의 '이번 주'가 같은 날짜 집합이어야 한다 — 주 시작 정의가 갈리면
/// 두 화면이 다른 합계를 보여준다. 정확한 리캡 API 는 P1 에서 확인해 채운다.
func testRecapWeekMatchesThePopoverWeekDefinition() { /* startOfWeek 비교 단언 */ }
```

### Task 19: 현재 기간 복귀 (`e21fb01` #367) / Task 20: 툴팁 정확값 (`5afeb2a` #368) — 배치 F 마감

- [ ] **절차 P ×2 (커밋 분리)** — MESSAGE `feat: return to the current period from usage recaps (upstream #367)` / `feat: show exact usage in recap chart tooltips (upstream #368)`
- [ ] **배치 게이트:** `swift test` 전체 PASS.

---

## 배치 G — SP1 이월 잔손질 (업스트림 커밋 없음)

### Task 21: 억제 키 리셋 + 슬립 중 재연결 억제 + 렌더 실측

**Files:** Modify `Core/UsageStore.swift`, `Core/AppLog.swift`(또는 `LogRepeatSuppressor`) / Test `UsageStoreTests.swift`, `LogRepeatSuppressorTests.swift`

- [ ] **Step 1 (TDD):** ① 성공 경로가 `claude-limits` 억제 키를 리셋 — RED: 오류→성공→같은 오류를 1시간 안에 다시 쓰면 기록돼야 한다는 테스트(`LogRepeatSuppressor.reset(key:)` 신설 + `UsageStore` 성공 분기에서 호출). ② 네트워크 복귀 refresh 가 `pollingSuspended` 중엔 발화하지 않음 — RED: suspend 후 `NetworkReachabilityMonitor.onReconnected` 경로 모사 호출 시 provider fetch 카운트 불변(`fetchCallCount` 재사용). 각각 RED→GREEN→커밋(영어, upstream 참조 없음 — 포크 자체 수정).
- [ ] **Step 2 (Review Focus 5 + 실물):** 임시 렌더 테스트(SP1 TempDexRender 방식, 커밋 금지)로 ① 쿼터바 마커+6색(사용/잔여 모드 각각) ② 트렌드 스택 ③ 리캡 화면을 오프스크린 렌더해 눈으로 확인. 마커·색이 스크린샷에 안 보이면 CALayer 필터 수식어(.brightness 등)를 의심하고 `SpriteView(silhouette:)` 식 그리기-단계 구현으로 교체. 확인 후 임시 테스트 삭제.
- [ ] **Step 3:** Dev 빌드 교체(`PTB_DEV=1 PTB_INSTALL=1 scripts/build-app.sh`) → 팝오버에서 트렌드·리캡·페이스 실물 확인(사용자 확인 요청).
- [ ] **배치 게이트 + 전체 마감:** `swift test` 전체 PASS → 최종 리뷰(신선 컨텍스트) → 머지는 사용자 확인.

## 자체 점검 메모 (스펙 대비)

- 스펙 배치 A~G 전 항목 매핑: A→T1–4, B→T5–6, C→T7–11, D→T12–14, E→T15–17, F→T18–20, G→T21.
  제외 3건(Cursor/Antigravity·#373·언어)은 스펙 §제외 그대로.
- Review Focus 5건 모두 담당 태스크에 단계 존재(T1·T9·T12·T18·T21).
- 테스트 스텁 4곳(T1 Step3 분류 단언·T9·T12·T18)은 업스트림 실 API 확인 전 확정 불가라 "P1 에서
  실명으로 채운다"로 명시 — 검사 대상(분류 보존·모드 일관·경계 클램프·주 정의 일치)이 고정 요구다.
- 릴리스 단계(스크린샷 신규 에셋·README·랜딩)는 스펙 §검증의 릴리스 메모대로 **릴리스 시점** 작업 —
  이 계획 밖(릴리스 트리거 시 CLAUDE.md 릴리스 절차가 집행).
