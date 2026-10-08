# SP1 Upstream Usage-Accuracy Port Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 업스트림(chattymin/PokeTokenBar)의 사용량 조사·폴링 수정 16건을 포크 코드에 이식한다.

**Architecture:** 커밋 단위 포팅. 각 태스크 = 업스트림 커밋 1개: 테스트를 먼저 이식해 RED 확인 → 구현 diff 적용(기계 적용 후 리젝트만 수동) → GREEN → 커밋. 같은 파일에 쌓이는 계열(Codex 리더, codex 탐지)은 업스트림 순서를 지킨다.

**Tech Stack:** Swift 6 / SwiftPM, XCTest. 업스트림 diff 가 소스다 — `git show <hash>`.

**Spec:** `docs/superpowers/specs/2026-10-08-sp1-usage-accuracy-port-design.md`

## Global Constraints

- 작업 브랜치: `port/sp1-usage-accuracy` (main 에서 분기, 끝나면 main 로컬 머지).
- 커밋 메시지 영어 + 원 커밋 참조: `<원 subject> (upstream #NNN)`. `Co-Authored-By` 트레일러 금지.
- 업스트림 헝크가 포크의 **키체인 규율**(자동 폴링은 키체인 금지)·**메뉴바 idle 규율**을 건드리면 그 헝크는 버린다 — CLAUDE.md 가 우선.
- 포크에 없는 파일(CursorUsageAPI·Kiro·Antigravity 등 신규 프로바이더)의 헝크는 전부 버린다.
- 전체 스위트는 **배치 경계 4곳**(Task 5·10·13·15 끝)에서 돌린다. 각 태스크 안에서는 해당 테스트 파일만.

## 공통 포팅 절차 (각 태스크의 "절차 P" 가 이것을 가리킨다 — 값만 태스크마다 다르다)

```bash
# P1. 업스트림 커밋 전체를 읽는다 (적용 전 필독 — 부분 이해로 베끼지 않는다)
git show <HASH>

# P2. 테스트부터 이식 (경로 재작성; Fixtures 포함 커밋은 같은 명령이 픽스처도 가져온다)
git show <HASH> -- 'Tests/*' | sed 's|PokeTokenBar|PokeDexBar|g' | git apply --reject
# *.rej 가 생기면: 그 테스트 파일을 열어 업스트림 내용을 포크 테스트 스타일로 수동 이식

# P3. RED 확인 — 이식한 테스트가 "기능 부재"로 실패하는지 본다 (컴파일 에러도 RED 로 침)
swift test --filter <TESTCLASS> 2>&1 | grep -E "error|failed"

# P4. 구현 적용
git show <HASH> -- 'Sources/*' | sed 's|PokeTokenBar|PokeDexBar|g' | git apply --reject
# *.rej 헝크는 손으로 이식. "버리는 헝크"(태스크별 명시)는 .rej 라도 이식하지 않는다.
# 적용 후 find . -name '*.rej' -o -name '*.orig' 로 잔해 정리.

# P5. GREEN — 태스크의 테스트 파일 통과 확인
swift test --filter <TESTCLASS>

# P6. 커밋
git add -A ':!*.rej' ':!*.orig' && git commit -m "<MESSAGE>"
```

## Review Focus

스펙이 암시하지만 업스트림 테스트가 안 덮는 실패 모드 5가지 — 각각 담당 태스크에 테스트/검증 단계를 박았다:

1. **#137 뒤 옛 사용량 캐시 blob 호환** — 형식이 바뀐 캐시를 옛 키로 읽으면 잘못 집계. → Task 1 Step 6.
2. **합계 회귀** — dedup 강화로 합계가 *늘면* 결함(줄어드는 건 중복 제거라 정상). → Task 16 의 전후 비교.
3. **#252 네트워크 플랩 시 refresh 폭주** — 디바운스 없으면 와이파이 출렁일 때마다 폴링. → Task 11 Step 3.
4. **#401 자가 점검이 정상 폴링과 중복 발화** — 멀쩡한 타이머 위에 겹치면 폴 간격이 반토막. → Task 14 Step 3.
5. **#402 가 포크의 "오늘 사용>0" 메뉴바 게이트를 깨는지** — 최근 프로바이더 유지가 컴팩트 표시 규율(미사용 프로바이더 노출 금지)과 충돌하면 포크 규율 우선. → Task 15 Step 3.

---

## 배치 ⓐ — Codex 리더 계열 (순서 고정: Task 1→2→3→4→5)

### Task 1: Codex 턴 내용 식별 (`a52c8c4`, #137)

**Files:**
- Modify: `Sources/PokeDexBar/Core/LocalUsageReader.swift`, `Sources/PokeDexBar/Core/LocalUsageCache.swift`
- Test: `Tests/PokeDexBarTests/LocalUsageReaderTests.swift`, `Tests/PokeDexBarTests/LocalUsageCacheTests.swift`, `Tests/PokeDexBarTests/Fixtures/CodexFork/*`, `Fixtures/CodexSubagent/*` (업스트림 픽스처 그대로)

**Interfaces:**
- Produces: `LocalUsageReader.parseCodexRollout(_:fmt:)`, `codexRolloutFiles(in:)`, `expandCodexParentClosure(...)`, `codexProbeByteLimit` — Task 2·3·4·5 가 이 위에 쌓인다.

- [ ] **Step 1–5: 절차 P** — HASH=`a52c8c4`, TESTCLASS=`LocalUsageReaderTests|LocalUsageCacheTests`, MESSAGE=`fix: identify Codex turns by content instead of file position (upstream #137)`
  - 이 커밋은 +682줄 대개편이라 리젝트가 많이 날 것 — P1 에서 diff 를 끝까지 읽고, 리젝트 헝크는 포크 파일의 해당 자리(함수 단위로 찾기)에 수동 이식한다.
  - 버리는 헝크: 없음(두 파일 모두 포크에 존재, Codex 경로는 분기 후 포크가 거의 안 건드림).
- [ ] **Step 6: 캐시 호환 가드 (Review Focus 1)** — 업스트림 diff 에서 `LocalUsageCache` 의 blob 버전/키가 올라갔는지 확인한다. 안 올라갔는데 blob 스키마가 바뀌었으면 포크에서 캐시 버전 상수를 올리고, 테스트 추가:

```swift
/// #137 은 Codex 파싱 결과의 모양을 바꿨다 — 옛 형식 blob 이 새 코드에 읽히면 잘못 집계되므로
/// 캐시 버전이 달라야 한다(버전 불일치 = 재파싱, 정답).
func testOldCacheBlobsAreInvalidatedAfterTheTurnIdentityChange() {
    XCTAssertNotEqual(LocalUsageCache.schemaVersion, 1,
                      "#137 포팅이 캐시 스키마 버전을 안 올렸다 — 옛 blob 이 그대로 읽힌다")
}
```
  (상수 이름은 포크 `LocalUsageCache.swift` 의 실제 버전 상수에 맞춘다 — 업스트림이 이미 올렸으면 이 테스트는 그 값 고정으로 대체.)
- [ ] **Step 7:** `swift test --filter "LocalUsageReaderTests|LocalUsageCacheTests"` PASS → 커밋.

### Task 2: 퇴화 fork 힌트 성능 (`b3910e3`, #146)

**Files:** Modify `Core/LocalUsageReader.swift` / Test `LocalUsageReaderTests.swift`

- [ ] **절차 P** — HASH=`b3910e3`, TESTCLASS=`LocalUsageReaderTests`, MESSAGE=`perf: stop a degenerate fork hint from parsing every rollout (upstream #146)`

### Task 3: 아카이브 후 Codex 사용량 보존 (`eff18bb`, #181)

**Files:** Modify `Core/LocalUsageReader.swift`, `Core/LocalUsageCache.swift` / Test `LocalUsageReaderTests.swift`, `LocalUsageCacheTests.swift`

- [ ] **절차 P** — HASH=`eff18bb`, TESTCLASS=`LocalUsageReaderTests|LocalUsageCacheTests`, MESSAGE=`fix: preserve Codex usage after session archiving (upstream #181)`

### Task 4: 대형 롤아웃 메모리 상한 (`7a7149f`, #184)

**Files:** Modify `Core/LocalUsageReader.swift` / Test: Create `Tests/PokeDexBarTests/CodexLargeRolloutPerformanceTests.swift` (업스트림 것 이식)

- [ ] **절차 P** — HASH=`7a7149f`, TESTCLASS=`CodexLargeRolloutPerformanceTests`, MESSAGE=`perf: bound memory while parsing large Codex rollouts (upstream #184)`

### Task 5: total-only 턴 + Fable 5.1 캐시 가격 (`232108c`, #279) — 배치 ⓐ 마감

**Files:** Modify `Core/LocalUsageReader.swift`, `Core/LocalUsageCache.swift`, `Core/ModelPricing.swift` / Test `LocalUsageReaderTests.swift`

- [ ] **절차 P** — HASH=`232108c`, TESTCLASS=`LocalUsageReaderTests`, MESSAGE=`fix: count Codex total-only turns and price Fable 5.1 cache reads (upstream #279)`
- [ ] **배치 게이트:** `swift test` 전체 PASS (실패 시 이 배치 안에서 해결 후 진행).

---

## 배치 ⓑ — 경계·탐지 (Task 6→10, 10 이 9 뒤여야 함: #369 는 #262 위)

### Task 6: 파싱 경계 토큰 clamp (`033853e`, #145)

**Files:** Modify `Core/LocalUsageReader.swift` / Test `LocalUsageReaderTests.swift`

- [ ] **절차 P** — HASH=`033853e`, TESTCLASS=`LocalUsageReaderTests`, MESSAGE=`fix: clamp token counts at the parsing boundary instead of trapping (upstream #145)`

### Task 7: 기본 루트 밖 Claude 로그 (`ce0d8eb`, #144)

**Files:** Modify `Core/BinaryLocator.swift`, `Core/LocalUsageCache.swift`, `Core/LocalUsageReader.swift`, `Core/Localization.swift`, `Core/OAuthLimitsProvider.swift`, `Core/UsageStore.swift` / Test `LocalUsageCacheTests.swift`, `LocalUsageReaderTests.swift`, `UsageStoreTests.swift`

- [ ] **절차 P** — HASH=`ce0d8eb`, TESTCLASS=`LocalUsageReaderTests|LocalUsageCacheTests|UsageStoreTests`, MESSAGE=`feat: find Claude usage logs outside the default project root (upstream #144)`
  - 주의: `OAuthLimitsProvider` 헝크가 키체인 접근 경로를 바꾸면 **그 헝크만 버린다**(포크 규율: 자동 폴링은 키체인 금지, `guard allowKeychainPrompt` 유지). P1 단계에서 이 파일 diff 를 특히 꼼꼼히 — 로그 루트 탐지와 무관한 변경이 섞여 있으면 분리.
  - `Localization` 헝크: 포크 `L` 구조체 스타일(ko/en/ja 3언어)에 맞춰 이식 — 업스트림은 언어가 더 많다(fr/es/de/pt/ru 값은 버린다).

### Task 8: 로그인 셸 env 해석 (`3f053d7`, #176)

**Files:** Create `Core/UsageEnvironment.swift` / Modify `Core/BinaryLocator.swift`, `Core/LocalAdditionalUsageProvider.swift`, `Core/LocalUsageReader.swift` / Test: Create `Tests/PokeDexBarTests/UsageEnvironmentTests.swift`

- [ ] **절차 P** — HASH=`3f053d7`, TESTCLASS=`UsageEnvironmentTests`, MESSAGE=`fix: resolve provider location env vars through the login shell (upstream #176)`
  - `LocalAdditionalUsageProvider` 헝크는 포크 버전이 많이 달라 수동 이식 전제.

### Task 9: ChatGPT.app 내장 codex 탐지 (`5f1ef52`, #262)

**Files:** Modify `Core/CodexRateLimitsProvider.swift` (+4줄) / Test: 업스트림 테스트 없음 — Task 10 의 `CodexRateLimitsProviderTests` 가 이 경로까지 덮는지 P1 에서 확인하고, 안 덮으면 거기에 케이스 추가

- [ ] **절차 P**(P2·P3 생략, P4 부터) — HASH=`5f1ef52`, MESSAGE=`fix: resolve the codex binary bundled inside ChatGPT.app for limit display (upstream #262)`

### Task 10: 중첩 CLI 번들 탐지 (`8c08e01`, #369) — 배치 ⓑ 마감

**Files:** Modify `Core/CodexRateLimitsProvider.swift` (+1줄) / Test: Create `Tests/PokeDexBarTests/CodexRateLimitsProviderTests.swift` (업스트림 것 이식 — Task 9 경로 포함 여부 확인, 미포함이면 아래 케이스 추가)

```swift
/// Task 9(#262)의 경로 — 업스트림 테스트가 안 덮으면 여기 추가한다.
func testFindsTheCodexBinaryInsideTheChatGPTAppBundle() {
    // BinaryLocator/CodexRateLimitsProvider 의 후보 경로 목록에 ChatGPT.app 내장 경로가 있는지
    // 를 값으로 확인한다 (실제 설치 여부와 무관한 목록 검사 — 설치 없는 CI 에서도 돈다).
    XCTAssertTrue(CodexRateLimitsProvider.candidateBundlePaths.contains {
        $0.contains("ChatGPT.app") }, "ChatGPT.app 내장 codex 후보 경로가 없다")
}
```
  (심볼 이름은 P1 에서 읽은 실제 업스트림 구현의 것으로 맞춘다 — 위는 형태 예시가 아니라 "목록 존재를 값으로 검사"하라는 고정 요구다.)

- [ ] **절차 P** — HASH=`8c08e01`, TESTCLASS=`CodexRateLimitsProviderTests`, MESSAGE=`fix(codex): discover the nested ChatGPT CLI bundle (upstream #369)`
- [ ] **배치 게이트:** `swift test` 전체 PASS.

---

## 배치 ⓒ — 폴링·갱신 (Task 11→13)

### Task 11: 네트워크 복귀 즉시 갱신 (`b34673a`, #252)

**Files:** Create `Core/NetworkReachabilityMonitor.swift` / Modify `Core/UsageStore.swift` / Test: Create `Tests/PokeDexBarTests/NetworkReachabilityTests.swift`

- [ ] **Step 1–2: 절차 P1–P5** — HASH=`b34673a`, TESTCLASS=`NetworkReachabilityTests`
- [ ] **Step 3: 플랩 디바운스 확인 (Review Focus 3)** — P1 에서 업스트림 구현에 디바운스/중복 억제(연속 satisfied 전이 무시)가 있는지 확인. 없으면 포크에서 "같은 상태로의 전이는 무발화" 가드와 테스트를 추가:

```swift
/// 와이파이가 출렁여 satisfied→satisfied 가 연달아 와도 refresh 는 전이당 1번이다.
func testRepeatedSatisfiedTransitionsFireOnlyOnce() {
    let monitor = NetworkReachabilityMonitor()
    var fired = 0
    monitor.onBecameReachable = { fired += 1 }
    monitor.simulatePathUpdate(satisfied: true)
    monitor.simulatePathUpdate(satisfied: true)
    XCTAssertEqual(fired, 1, "같은 상태 반복에 refresh 가 중복 발화했다")
}
```
  (`simulatePathUpdate` 가 업스트림에 없으면 `#if DEBUG` 테스트 심으로 추가 — NWPathMonitor 실경로는 xctest 에서 못 돌린다.)
- [ ] **커밋** — MESSAGE=`feat: trigger immediate refresh upon network reconnection (upstream #252)`

### Task 12: 추가 프로바이더 clamp (`878a0be`, #307)

**Files:** Modify `Core/LocalAdditionalUsageProvider.swift` / Test `LocalAdditionalUsageTests.swift`

- [ ] **절차 P** — HASH=`878a0be`, TESTCLASS=`LocalAdditionalUsageTests`, MESSAGE=`fix: clamp extra-provider token counts so a corrupt log cannot trap (upstream #307)`
  - 버리는 헝크: `CursorUsageAPI.swift`(포크에 없음), `CursorUsageTests`·`KiroUsageTests`(포크에 없음).

### Task 13: 로그 소음 2건 (`a94b3da` #360 + `5f6a4f0` #361) — 배치 ⓒ 마감

**Files:** Create `Core/LogRepeatSuppressor.swift` / Modify `Core/AppLog.swift`, `Core/LocalUsageReader.swift`, `Core/UsageStore.swift`, `Core/ModelPricing.swift` / Test: Create `LogRepeatSuppressorTests.swift`, Modify `ModelPricingTests.swift`

- [ ] **절차 P ×2 (커밋 2개 분리)** — ① HASH=`a94b3da`, TESTCLASS=`LogRepeatSuppressorTests`, MESSAGE=`fix: stop unchanged status lines from filling the log every poll (upstream #360)` — 버리는 헝크: `CursorRateLimitsProvider`·`CursorUsageAPI`. ② HASH=`5f6a4f0`, TESTCLASS=`ModelPricingTests`, MESSAGE=`fix: log each unpriced model once so a missing price row is noticed (upstream #361)`
- [ ] **배치 게이트:** `swift test` 전체 PASS.

---

## 배치 ⓓ — 복원력 (Task 14→15)

### Task 14: 폴링 자가 점검 (`906bbb9`, #401)

**Files:** Modify `Core/UsageStore.swift` / Test `UsageStoreTests.swift`

- [ ] **Step 1–2: 절차 P1–P5** — HASH=`906bbb9`, TESTCLASS=`UsageStoreTests`
- [ ] **Step 3: 정상 폴링 무간섭 확인 (Review Focus 4)** — 업스트림 테스트에 "타이머가 살아 있으면 자가 점검이 재시작하지 않는다" 케이스가 있는지 P1 에서 확인, 없으면 추가:

```swift
/// 자가 점검은 폴링이 죽었을 때만 살린다 — 멀쩡한 타이머를 재시작하면 간격이 뒤틀린다.
func testTheWatchdogLeavesAHealthyPollerAlone() {
    // 마지막 틱이 최근(간격 이내)이면 watchdog 경로가 refresh 를 안 부르는지를
    // 업스트림이 노출한 판정 함수(순수)로 검사한다 — 실제 함수명은 P1 에서 확인해 맞춘다.
}
```
- [ ] **커밋** — MESSAGE=`fix: resume suspended polling when screensDidWake is missed (upstream #401)`

### Task 15: 달력 리셋 후 프로바이더 유지 (`11eebe6`, #402) — 배치 ⓓ 마감

**Files:** Modify `Core/LocalUsageReader.swift`, `Core/Models.swift`, `Core/UsageProvider.swift`, `Core/UsageStore.swift` / Test `LocalUsageReaderTests.swift`, `UsageStoreTests.swift`

- [ ] **Step 1–2: 절차 P1–P5** — HASH=`11eebe6`, TESTCLASS=`LocalUsageReaderTests|UsageStoreTests`
  - 버리는 헝크: `MonthDailyTrendTests`(포크에 트렌드 없음 — SP2 에서 온다. 그 테스트 헝크가 소스 헝크와 엮여 있으면 트렌드 관련 소스 헝크도 함께 버리고 메모를 SP2 스펙에 남긴다).
- [ ] **Step 3: 메뉴바 게이트 보존 (Review Focus 5)** — 포크의 `menuLines` "오늘 토큰>0" 게이트가 그대로인지: 기존 `testMenuLinesAllCombinations` 계열이 전부 통과해야 하고, "어제만 쓴 프로바이더가 메뉴바에 안 뜬다" 케이스가 없으면 추가:

```swift
/// #402 는 팝오버 탭 유지용이다 — 메뉴바 컴팩트 표시는 여전히 '오늘 사용>0' 만 보인다.
func testYesterdayOnlyProvidersStayOutOfTheMenuBar() {
    // usedToday 가 비고 recentlyUsed 에만 있는 프로바이더로 menuLines 를 만들었을 때
    // 그 프로바이더 줄이 없는지 확인 — 함수·필드명은 P1 적용 결과에 맞춘다.
}
```
- [ ] **커밋** — MESSAGE=`fix: keep recently used providers' tabs and limits across calendar resets (upstream #402)`
- [ ] **배치 게이트:** `swift test` 전체 PASS.

---

### Task 16: 합계 회귀 검증 + 실측 + 머지

- [ ] **Step 1: 합계 전후 비교 (Review Focus 2).** 포팅 브랜치와 main 양쪽에서 같은 실로그로 오늘/주/월 합계를 뽑아 비교한다:

```bash
# main 과 port 브랜치 각각에서 (PTB_INSPECT 식 임시 테스트로) 합계 출력 → diff
git checkout main && swift test --filter TempTotalsProbe 2>&1 | grep "totals:"
git checkout port/sp1-usage-accuracy && swift test --filter TempTotalsProbe 2>&1 | grep "totals:"
```
  `TempTotalsProbe` 는 실행 시점에 작성하는 일회성 테스트(실사용 캐시를 **읽기만** — 업스트림 #359 가 고친 "테스트가 사용자 캐시를 재작성" 함정을 밟지 않게 쓰기 경로 금지): `LocalUsageProvider` 로 오늘/주/월 합계를 출력. **감소 또는 동일 = 정상, 증가 = 결함**(원인 규명 전 머지 금지). 확인 후 삭제.
- [ ] **Step 2: Dev 빌드 실측** — `PTB_DEV=1 PTB_INSTALL=1 scripts/build-app.sh` → 로그에서 ① 오늘 합계가 Step 1 과 일치 ② codex 한도: ChatGPT.app 설치 기기면 `binary not found` 소멸 ③ 같은 상태줄이 폴마다 반복되지 않음.
- [ ] **Step 3: 머지** — `swift test` 전체 PASS 확인 → main 로컬 머지, 브랜치 삭제. (릴리스는 SP2 뒤 또는 사용자 지시 시.)

## 자체 점검 메모 (스펙 대비)

- 스펙 16항목 전부 태스크에 매핑: 1→T1, 2→T6, 3→T7, 4→T2, 5→T9, 6→T3, 7→T4, 8→T8, 9→T11, 10→T12, 11→T5, 12→T13①, 13→T13②, 14→T10, 15→T14, 16→T15. 제외 7건은 스펙 §제외 그대로.
- Review Focus 5건 전부 담당 태스크에 단계 존재(T1·T16·T11·T14·T15).
- 테스트 심볼 이름 3곳(T10·T14·T16)은 업스트림 실구현을 읽기 전엔 확정 불가라 "P1 에서 실명으로 맞춘다"로 명시 — 형태가 아니라 검사 대상(값 검사·무발화·게이트 보존)이 고정 요구다.
