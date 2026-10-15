# SP3 Claude Accounts/Limits Port Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 업스트림의 Claude 계정·한도 11커밋 + SP2 이월 1건을 포크에 이식한다(테스트 안전 게이트 → 계정 식별·키체인 정리 → 세션 키 → 수동 갱신 → 다중 계정 → 메뉴바 이월).

**Architecture:** SP1·SP2 와 같은 커밋 단위 포팅, 실행은 업스트림 시간순 — 단 **#355(라이브 호출 게이트)만 맨 앞으로 당긴다**(스펙 배치 E 의 권장: 이후 모든 태스크의 테스트가 실 자격증명으로 외부 엔드포인트를 때리지 않게 하는 보호를 먼저 세운다). `OAuthLimitsProvider` 는 포크 271줄 vs 업스트림 574줄이라 **전 태스크 수동 포팅 전제**(기계 적용은 시도하되 리젝트가 기본). 포크 키체인 규율(`allowKeychainPrompt` 게이트 + `testAutoRefreshUsesNoPromptPathManualUsesPromptPath`)은 불변 조건이다.

**Tech Stack:** Swift 6 / SwiftPM, XCTest. 소스는 업스트림 diff — `git show <hash>`.

**Spec:** `docs/superpowers/specs/2026-10-15-sp3-claude-accounts-port-design.md`

## Global Constraints

- 작업 브랜치: `port/sp3-claude-accounts` (main 분기, 완료 후 로컬 머지 — 머지는 사용자 확인).
- 커밋 영어 + `(upstream #NNN)` 참조, `Co-Authored-By` 금지.
- `Localization` 헝크는 **ko/en/ja 만** — 업스트림 추가 언어 값은 버린다(SP2 의 3-문자열 트림 regex 재사용 가능).
- 포크에 없는 파일(Antigravity·Cursor·Aside·Kiro 등) 헝크·테스트는 전부 버린다.
- `UserDefaults` 키 이름은 업스트림과 동일 유지(이후 포팅 diff 최소화).
- 포크 키체인 규율 우선: 자동 폴 경로에서 Keychain 읽기 추가 금지. 충돌 헝크는 버리고 장부에 기록.
- CompanionStore 참조는 PlayerStore 로 치환, 없는 게임 모델 의존 테스트는 의도를 포크 모양으로 재작성.
- 커밋은 `git add -A ':!.superpowers' ':!AGENTS.md'` + 사전 `find . -name '*.rej' -o -name '*.orig'` 청소. **`.rej` 는 파일별 수동 처리 후에만 삭제**(SP1·SP2 에서 두 번 밟은 일괄-삭제 사고 방지).
- 전체 스위트는 배치 경계 6곳: Task 1(E)·5(A)·7(B)·8(C)·11(D)·12(F) 끝.

## 공통 포팅 절차 P (태스크의 "절차 P"는 이것 — 값만 다르다)

```bash
# P1. 커밋 전체 정독 (적용 전 필수 — 버릴 헝크·치환 지점을 여기서 정한다)
git show <HASH>
# P2. 테스트 선이식 (경로 치환; 버릴 테스트 파일은 태스크에 명시)
git show <HASH> -- 'Tests/*' | sed 's|PokeTokenBar|PokeDexBar|g' | git apply --reject
# P3. RED — 기능 부재로 실패 확인(컴파일 에러 포함). 불가 시 태스크에 명시된 대체 검증.
swift test --filter <TESTCLASS> 2>&1 | grep -E "error|failed"
# P4. 소스 적용 → *.rej 는 함수 단위 수동 이식, 버릴 헝크는 이식하지 않는다
git show <HASH> -- 'Sources/*' | sed 's|PokeTokenBar|PokeDexBar|g' | git apply --reject
# P5. GREEN
swift test --filter <TESTCLASS>
# P6. 커밋
find . -name '*.rej' -o -name '*.orig' | xargs rm -f
git add -A ':!.superpowers' ':!AGENTS.md' && git commit -m "<MESSAGE>"
```

## Review Focus

1. **#355 게이트의 경계 정확성** — 게이트가 자격증명 읽기 *앞*이면 KeychainAutoPathTests 류가 아무것도 안 보게 되고, 네트워크 *뒤*면 실 호출이 샌다. 자격증명 읽기 뒤·네트워크 앞이어야 한다. → Task 1 Step 3.
2. **계정 1개 사용자 불변** — 다중 계정 코드가 들어와도 추가 계정이 없는 기존 사용자에게 탭·라벨·알림 tier 키·UserDefaults 가 하나도 안 변해야 한다(세이브·알림 dedup 호환). → Task 9 Step 4.
3. **계정 폴더 오탐** — `~/.claude-backup`, `~/.claude-2024-snapshot` 같은 백업/임시 폴더나 credentials 없는 폴더가 계정 탭으로 오인되면 유령 계정이 생긴다. → Task 9 Step 3.
4. **#344 × SP1 dedup 상호작용** — 포크는 이미 #129(포크 세션 재생 제외)·서브에이전트 제외를 갖고 있다. 귀속을 위해 세션 id *전부*를 보존하는 #344 가 "턴 전역 유일 id dedup"을 깨면 이중집계가 재발한다. → Task 10 Step 3.
5. **세션 키 만료 UX 혼선** — OAuth 만료와 세션 키 만료는 복구 버튼이 다르다(키체인 갱신 vs 키 재입력). 만료 상태가 서로를 덮어쓰면 사용자가 엉뚱한 버튼으로 유도된다. → Task 6 Step 3.

---

## 배치 E(선행) — 테스트 안전 게이트

### Task 1: 라이브 한도 호출 게이트 (`671c1ec`, #355)

**Files:**
- Modify: `Core/OAuthLimitsProvider.swift`(usage·profile 호출 앞 — profile 은 Task 2 전이면 usage 만), `Core/UsageStore.swift`, `Core/AppEnv.swift`(또는 `AppEnv` 가 사는 파일 — P1 에서 확인; 포크에 `AppEnv.isBundledApp` 이 이미 있다)
- Test: `Tests/PokeDexBarTests/LiveCredentialCallGateTests.swift`(신설 — 업스트림 파일 이식). **버림**: Cursor/Antigravity 경계 헝크·관련 단언.

**Interfaces:**
- Produces: `AppEnv.allowsLiveLimitsFetch: Bool`(.app 번들 ∨ `PTB_PARITY=1` ∨ `AppEnv.allowLiveFetchForTesting`), `LimitsError.liveFetchNotPermitted`. 이후 모든 태스크의 네트워크 경계가 이 게이트를 쓴다.

- [ ] **Step 1: 절차 P** — HASH=`671c1ec`, TESTCLASS=`LiveCredentialCallGateTests`, MESSAGE=`fix: stop the test suite from calling live limits endpoints with the user's login (upstream #355)`. 주의: 이 시점의 포크엔 `SessionKeyLimitsProvider`·profile 호출이 아직 없다 — 해당 헝크는 **보류 목록**으로 장부에 적고, 각 기능이 들어오는 Task 2(profile)·Task 6(세션 키)에서 게이트를 같이 심는다.
- [ ] **Step 2: 기존 실-프로바이더 기본값 확인.** `UsageStore.init` 의 `claudeLimitsProvider`/`codexLimitsProvider` 기본값 경로가 게이트 뒤에 있는지 grep 으로 확인하고, codex 프로세스 실행(`CodexLimitsProvider` 류)도 외부 부작용이면 같은 게이트를 적용.
- [ ] **Step 3: 게이트 경계 핀 (Review Focus 1).** 업스트림 테스트가 이미 "자격증명이 있어도 네트워크에서 멈춘다"를 검증한다 — 포크 쪽에 다음 대조군이 없으면 추가:

```swift
/// 게이트는 네트워크 경계다 — 자격증명 *읽기*는 여전히 일어나야 KeychainAutoPathTests 류가 유효하다.
func testTheGateStopsTheCallNotTheCredentialRead() async {
    // 파일 기반 자격증명 픽스처를 둔 뒤 fetch — LimitsError.liveFetchNotPermitted 로 던지는지,
    // 그리고 그 전에 자격증명 읽기 카운터(or 파일 접근 관찰)가 1 이상인지 단언.
}
```

- [ ] **Step 4: 전체 게이트.** `swift test` 전체 PASS + 로그에 외부 호출 흔적 없음.

## 배치 A — 계정 식별·키체인 정리

### Task 2: 공식 한도의 계정 라벨 (`40f4108`, #199)

**Files:**
- Modify: `Core/Models.swift`(`LimitStatus` 에 `accountEmail`/`accountOrganizationName`/`accountDisplay`), `Core/OAuthLimitsProvider.swift`(+`AccountIdentity`·`OAuthProfileCache`·`OAuthProfileData`), `Core/Localization.swift`(ko/en/ja), `UI/PopoverView.swift`(plan 행 밑 캡션)
- Test: 업스트림 `PokeTokenBarTests.swift` 헝크 → 포크 `Tests/PokeDexBarTests/PokeTokenBarTests.swift` 로.

**Interfaces:**
- Consumes: Task 1 의 `AppEnv.allowsLiveLimitsFetch`.
- Produces: `AccountIdentity(email:organizationName:)`, `OAuthProfileCache.shared.identity(accessToken:) async -> AccountIdentity?`(토큰별 캐시), `OAuthProfileData.identity(from: Data) -> AccountIdentity?`(순수 파서). Task 9 의 계정 탭 라벨이 재사용.

- [ ] **Step 1: 절차 P** — HASH=`40f4108`, TESTCLASS=`PokeTokenBarTests`, MESSAGE=`feat: label official limits with the owning account (upstream #199)`
- [ ] **Step 2: Task 1 보류분 적용.** profile 호출 앞에 `guard AppEnv.allowsLiveLimitsFetch else { return nil }` — #355 가 이 지점에 둔 게이트를 그대로 옮긴다(장부 보류 목록에서 지움).
- [ ] **Step 3: 포크 게이트 확인.** profile 호출은 **이미 가진 액세스 토큰**으로만 — Keychain 추가 읽기가 없음을 P1 에서 확인(있으면 그 헝크는 버리고 토큰 전달형으로 수동 이식). `testAutoRefreshUsesNoPromptPathManualUsesPromptPath` 그대로 PASS.

### Task 3: 제자리 계정 전환 감지 (`3214f83`, #227/#228)

**Files:**
- Modify: `Core/OAuthLimitsProvider.swift`(`OAuthAccessTokenCache` — 캐시 히트 전 `~/.claude/.credentials.json` 피크)
- Test: `Tests/PokeDexBarTests/CredentialSwitchCacheTests.swift`(신설 — 업스트림 파일 이식). **버림**: Antigravity 토큰 캐시 헝크, README 헝크.

**Interfaces:**
- Consumes: 포크 `OAuthAccessTokenCache.accessToken(allowKeychainPrompt:bypassCache:)`.
- Produces: 캐시 무효화 규칙 "파일 mtime/내용 변화 시 캐시 버림" — Task 8 의 bypassCache 와 상보.

- [ ] **Step 1: 절차 P** — HASH=`3214f83`, TESTCLASS=`CredentialSwitchCacheTests`, MESSAGE=`fix: pick up an in-place Claude account switch on auto-poll (upstream #227)`
- [ ] **Step 2: 자동 경로 무접촉 재확인.** 피크는 파일만 — Keychain 은 여전히 수동 전용. 회귀 테스트 PASS 를 커밋 전 확인.

### Task 4: 다중 Keychain 항목 해석 (`e81e620`, #232)

**Files:**
- Modify: `Core/OAuthLimitsProvider.swift`(or `Core/KeychainAccess.swift` — P1 에서 수동 경로의 Keychain 질의가 사는 쪽)
- Test: 업스트림 `PokeTokenBarTests.swift` 헝크(42줄) → 포크 동명 파일.

**Interfaces:**
- Produces: 수동 갱신 경로의 후보 항목 열거(여러 'Claude Code-credentials' 항목에서 유효 토큰 선택). Task 5 가 이 열거에 우선순위를 얹는다.

- [ ] **Step 1: 절차 P** — HASH=`e81e620`, TESTCLASS=`PokeTokenBarTests`, MESSAGE=`fix: resolve Claude account OAuth across multiple Keychain entries (upstream #232)`
- [ ] **Step 2: 수동 전용 확인.** 열거가 `allowKeychainPrompt == true` 분기 안에서만 도는지 소스로 확인(자동 경로에 새 `SecItemCopyMatching` 이 생기면 포크 규율 위반 — 그 헝크는 수동 분기로 옮겨 이식).

### Task 5: 사용자 계정 우선 + 프롬프트 폭탄 방지 (`c9c016d`, #280)

**Files:**
- Modify: `Core/OAuthLimitsProvider.swift`(후보 정렬: NSUserName() > email > general > unknown/none; `errSecUserCanceled`/`errSecAuthFailed` 즉시 중단; `errSecItemNotFound` 시 무스코프 쿼리 생략)
- Test: 업스트림 `PokeTokenBarTests.swift` 헝크(83줄, 테스트 7개) → 포크 동명 파일.

**Interfaces:**
- Consumes: Task 4 의 후보 열거.

- [ ] **Step 1: 절차 P** — HASH=`c9c016d`, TESTCLASS=`PokeTokenBarTests`, MESSAGE=`fix: prioritize the user account over MCP placeholders in Keychain lookup (upstream #280)`
- [ ] **Step 2: 배치 A 전체 게이트.** `swift test` 전체 PASS.

## 배치 B — 세션 키 경로

### Task 6: claude.ai 세션 키로 한도 조회 (`8953ea8`, #241) — SP3 2대 항목 ①

**Files:**
- Create: `Core/SessionKeyLimitsProvider.swift`(314줄 — `SessionKeyHTTPResponse`·`SessionKeyHTTPClient`·`URLSessionSessionKeyClient`·`SessionKeyCredential`·`SessionKeyStore`·`SessionKeyOrganization`·`SessionKeyManaging`·`SessionKeyLimitsProvider`·`ChainedLimitsProvider`)
- Modify: `Core/OAuthLimitsProvider.swift`(`LimitsError` 확장), `Core/UsageStore.swift`(기본 프로바이더를 `ChainedLimitsProvider(...)` 로, `sessionKeyConfigured`/`sessionKeySelectedOrgID`/`LimitsAuthExpiry(.oauth/.sessionKey)`), `UI/SettingsView.swift`(Advanced 세션 키 입력), `UI/PopoverView.swift`, `Core/Localization.swift`(ko/en/ja)
- Test: `Tests/PokeDexBarTests/SessionKeyLimitsTests.swift`(신설, 555줄 — HTTP 는 전부 `SessionKeyHTTPClient` 픽스처), `SessionKeyStoreLocationTests`, `UsageStoreTests` 헝크(250줄). **버림**: README 헝크(릴리스 시점).

**Interfaces:**
- Consumes: Task 1 게이트(이 커밋의 `URLSessionSessionKeyClient` 실 호출 앞 게이트 = Task 1 보류분 둘째 — 여기서 심고 장부에서 지움), 포크 `ClaudeLimitsProviding`(시그니처 동일: `fetch(allowKeychainPrompt:)`).
- Produces: `SessionKeyLimitsProvider.shared: SessionKeyManaging`, `ChainedLimitsProvider`(세션 키 → OAuth 폴백), `UsageStore.sessionKeyConfigured/ sessionKeySelectedOrgID`. Task 7 의 안내 UI·Task 11 의 계정별 키가 이 위에 선다.

- [ ] **Step 1: 절차 P** — HASH=`8953ea8`, TESTCLASS=`SessionKeyLimitsTests|SessionKeyStoreLocationTests|UsageStoreTests`, MESSAGE=`feat: fetch official limits with a claude.ai session key (upstream #241)`
- [ ] **Step 2: 포크 접합 확인.** ① `disableKeychainAccess && !sessionKeyConfigured` 분기 — 포크의 기존 `disableKeychainAccess` 플래그 이름과 대조(다르면 포크 이름 유지) ② `SessionKeyStore` 의 저장 파일 경로·권한(0600) 확인 — 앱 소유 **Keychain 항목 신설 금지** 규칙(CLAUDE.md #58)에 부합하는 파일 저장인지 ③ 429 는 기존 `applyLimitsBackoffIfRateLimited` 백오프와 한 체계로.
- [ ] **Step 3: 만료 상태 분리 핀 (Review Focus 5).** 업스트림 `LimitsAuthExpiry` 가 oauth/sessionKey 를 구분한다 — 포크의 기존 `limitsAuthExpired`(단일 Bool) 치환 후, 다음을 테스트로 고정:

```swift
/// OAuth 만료와 세션 키 만료는 복구 버튼이 다르다 — 한쪽 성공이 다른 쪽 만료 안내를 지우면 안 된다.
func testSessionKeyExpiryIsNotClearedByAnOAuthSuccess() async {
    // 세션 키 401 → .sessionKey 만료 표시 → OAuth 폴백 성공 → 만료 안내가 .sessionKey 로 유지되는지
    // (키를 지우거나 재입력할 때까지), 반대 조합도 대조군으로.
}
```

- [ ] **Step 4: 실검증 준비(실행 아님).** `scripts/probe-session-key.swift` 는 **업스트림 저장소에 없다**(커밋 주석만 참조) — 만들지 않는다. 대신 Task 12 의 Dev 빌드 실측 체크리스트에 "세션 키 입력 → 자동 폴 2회에서 한도 갱신·프롬프트 0회" 항목을 둔다. curl 검증은 불가(Cloudflare 챌린지)임을 장부에 기록.

### Task 7: 키체인 한계 안내 팝오버 (`7898065`, #275)

**Files:**
- Modify: `UI/PopoverView.swift`(앰비언트 도움 팝오버), `UI/SettingsView.swift`(네비게이트 오픈 시 세션 키 필드로 자동 스크롤·포커스), `Core/Localization.swift`(ko/en/ja — 업스트림 38줄에서 트림)
- Test: `Tests/PokeDexBarTests/SessionKeySettingsRenderingTests.swift`(신설 — 렌더 픽스처; 데스크톱 포커스 검사는 업스트림도 분리해 둠, 호스트 불가 단언은 버림)

**Interfaces:**
- Consumes: Task 6 의 `sessionKeyConfigured`, 설정 네비게이션(포크의 설정 열기 경로 — P1 에서 확인).

- [ ] **Step 1: 절차 P** — HASH=`7898065`, TESTCLASS=`SessionKeySettingsRenderingTests`, MESSAGE=`feat: add an ambient Claude Keychain help popover with session-key navigation (upstream #275)`
- [ ] **Step 2: 배치 B 전체 게이트.** `swift test` 전체 PASS.

## 배치 C — 수동 갱신·전환 반영

### Task 8: 수동 갱신은 유효 캐시도 건너뛴다 (`3272509`, #302)

**Files:**
- Modify: `Core/OAuthLimitsProvider.swift`(수동 refresh 가 `bypassCache: true` — 포크에 이미 있는 매개변수와 접합), `Core/KeychainAccess.swift`(6줄), `UI/PopoverView.swift`(푸터 펫 토글 — **포크에 동등 기능이 이미 있으면 스킵하고 장부에 기록**)
- Test: `CredentialSwitchCacheTests`(112줄 추가 — Task 3 파일에 누적), `PopoverNavigationTests` 헝크(펫 토글 스킵 시 같이 버림). **버림**: Antigravity 헝크.

**Interfaces:**
- Consumes: Task 3 의 캐시 무효화 규칙(파일 피크) — 이 커밋은 "401 전엔 안 보이던 전환"을 수동 경로에서 마저 닫는다.

- [ ] **Step 1: 절차 P** — HASH=`3272509`, TESTCLASS=`CredentialSwitchCacheTests`, MESSAGE=`fix: make a manual limits refresh re-read credentials past a valid cache (upstream #302)`
- [ ] **Step 2: 배치 C 전체 게이트.** `swift test` 전체 PASS.

## 배치 D — 다중 계정

### Task 9: 여러 Claude 계정 추적 (`e5b4800`, #327) — SP3 2대 항목 ②

**Files:**
- Create: `Core/ClaudeAccountRoots.swift`(315줄 — 폴더 감지·수동 등록), `Core/ClaudeAccountUsage.swift`(199줄 — 계정 귀속)
- Modify: `Core/UsageStore.swift`(+502줄 급: `claudeAccounts: [ClaudeAccountLimits]`·`trackedClaudeAccount`·`claudeTrackedAccountMode`·`claudeCurrentBlock(for:)`·`buildLimitWindows()`·계정별 만료/429 격리), `Core/OAuthLimitsProvider.swift`(폴더별 토큰 캐시: `.credentials.json` 또는 `Claude Code-credentials-<sha256 접두>` Keychain 항목 — **수동 경로 한정**), `Core/LocalUsageReader.swift`/`Core/LocalUsageCache.swift`(계정 귀속 접합), `UI/PopoverView.swift`(+276줄: 계정 탭), `UI/SettingsView.swift`(Advanced 계정 등록), `UI/FloatingPetPanel.swift`(기본 계정 따름 유지), `Core/Localization.swift`(ko/en/ja), `PokeDexBarApp.swift`(2줄)
- Test: `Tests/PokeDexBarTests/AdditionalClaudeAccountsTests.swift`(신설 — 업스트림 1,925줄에서 **선별**: Antigravity·CompanionStore·LocalizationInterpolation 의존 단언 버리고, 사탕/알림 커버리지는 포크 알림 구조(`evaluateLimitAlerts`)로 재작성), `KeychainAutoPathTests` 헝크.

**Interfaces:**
- Consumes: Task 2 `AccountIdentity`(탭 라벨), Task 6 `ChainedLimitsProvider`, 포크 `UsageStore.evaluateLimitAlerts(windows:warn:crit:tiers:)`.
- Produces: `ClaudeAccountRoots`(감지), `ClaudeAccountLimits`(Identifiable — 탭 모델), `ClaudeAccountUsage`/`ClaudeAccountUsageAttribution`/`ClaudePromptHistory`(귀속 — Task 10 이 확장), `UsageStore.claudeAccounts`·`trackedClaudeAccount`·`buildLimitWindows()`. Task 11·12 가 이 표면을 쓴다.

- [ ] **Step 1: 절차 P** — HASH=`e5b4800`, TESTCLASS=`AdditionalClaudeAccountsTests|KeychainAutoPathTests|UsageStoreTests`, MESSAGE=`feat: track several Claude accounts (upstream #327)`. P1 에서 버릴 헝크 목록을 장부에 먼저 적는다(README·Antigravity·CompanionStore·LocalizationInterpolation).
- [ ] **Step 2: 포크 접합.** ① 포크 `LocalUsageReader` 의 기존 `CLAUDE_CONFIG_DIR` 다중 루트 스캔과 `ClaudeAccountRoots` 감지를 **단일 소스**로(두 곳이 따로 폴더를 열거하면 안 된다 — CLAUDE.md `BinaryLocator` 단일 소스 규칙과 같은 부류) ② 알림은 `buildLimitWindows()` 가 주는 key 로 — 휘발성 필드(resets_at)를 key 에 넣지 않는 기존 규칙 유지 ③ 메뉴바·플로팅 펫·5h forecast 는 기본 계정 따름(업스트림 명시) — 컴팩트 게이트(오늘 사용>0) 그대로.
- [ ] **Step 3: 폴더 오탐 가드 (Review Focus 3).**

```swift
/// 감지는 "Claude Code 가 로그인한 config 폴더"다 — 백업·빈 폴더는 계정이 아니다.
func testBackupAndEmptyFoldersAreNotDetectedAsAccounts() throws {
    // 임시 홈에 ~/.claude-backup(자격증명 없음)·~/.claude-old(빈 폴더)·~/.claude-work(.credentials.json
    // 있음)을 만들고 ClaudeAccountRoots 감지가 work 만 돌려주는지. 업스트림에 같은 테스트가 있으면
    // 그것을 쓰되, '자격증명 없는 폴더' 케이스가 빠져 있으면 이 대조군을 추가.
}
```

- [ ] **Step 4: 계정 1개 불변 핀 (Review Focus 2).**

```swift
/// 추가 계정이 없는 기존 사용자: 탭 없음, 라벨 없음, 알림 tier 키·UserDefaults 키가 종전과 동일.
func testASingleAccountUserSeesNoMultiAccountSurface() async {
    // 추가 루트 0 상태로 refresh → claudeAccounts 가 기본 계정뿐, buildLimitWindows() 의 key 가
    // 기존 단일 계정 시절 키와 동일(알림 dedup 이 이어짐), 팝오버 계정 탭 조건이 false.
}
```

- [ ] **Step 5: 커밋**(절차 P 의 P6).

### Task 10: 포크 세션 사용량의 원본 계정 귀속 (`e76a8e0`, #344)

**Files:**
- Modify: `Core/ClaudeAccountUsage.swift`(`owner(sessions:at:accounts:) -> String?` — 복수 세션 id 보존·최신 프롬프트 우선), `Core/LocalUsageReader.swift`(`Entry.claudeSessionIDs` — 턴이 발견된 모든 세션 id)
- Test: `AdditionalClaudeAccountsTests` 헝크(26줄 — 원본·분기 복사본을 양쪽 입력 순서로).

**Interfaces:**
- Consumes: Task 9 의 `ClaudeAccountUsage`·`ClaudePromptHistory`.
- Produces: `ClaudeAccountUsage.owner(sessions:at:accounts:)`(순수 — 분기 세션의 미래 프롬프트로 과거 턴을 귀속하지 않는다).

- [ ] **Step 1: 절차 P** — HASH=`e76a8e0`, TESTCLASS=`AdditionalClaudeAccountsTests`, MESSAGE=`fix: keep forked usage with its original account (upstream #344)`
- [ ] **Step 2: 상호작용 확인.** 포크 SP1 의 dedup(#129 재생 제외·서브에이전트 제외)와 겹치는 지점을 P1 에서 대조 — 귀속은 dedup *후* 의 턴에 세션 id 목록만 더하는 구조여야 한다.
- [ ] **Step 3: 이중집계 불변 핀 (Review Focus 4).**

```swift
/// 세션 id 를 전부 보존해도 dedup 키는 여전히 턴 전역 유일 id — 합계는 정확히 1회.
func testProvenancePreservationDoesNotDoubleCount() throws {
    // 같은 턴의 원본·분기 복사본 2파일 → 합계 1회 + owner 가 원본 계정. (업스트림 회귀 가드가
    // 이미 '양쪽 입력 순서'를 덮는다 — 포크 서브에이전트 제외와의 조합 케이스만 추가.)
}
```

### Task 11: 계정별 세션 키 (`eed5b73`, #346)

**Files:**
- Modify: `Core/SessionKeyLimitsProvider.swift`(+21줄: 루트별 키 저장), `Core/UsageStore.swift`(+110줄: `accountSessionKeyPaths`·`saveAccountSessionKey(_:for:)`·`clearAccountSessionKey(for:)`·`accountSessionKeyError(for:)`·`validatingAccountSessionKeyPath`), `UI/SettingsView.swift`(계정 행마다 키 입력), `UI/PopoverView.swift`, `Core/Localization.swift`(ko/en/ja)
- Test: `Tests/PokeDexBarTests/AccountSessionKeyTests.swift`(신설, 319줄 — HTTP 픽스처). **버림**: LocalizationInterpolationTests 헝크.

**Interfaces:**
- Consumes: Task 6 `SessionKeyStore`·`SessionKeyManaging`, Task 9 `claudeAccounts`·계정 루트 경로.
- Produces: `UsageStore.saveAccountSessionKey(_ raw: String, for rootPath: String) async` 등 — Task 12 와 Dev 실측이 쓰는 최종 표면.

- [ ] **Step 1: 절차 P** — HASH=`eed5b73`, TESTCLASS=`AccountSessionKeyTests`, MESSAGE=`feat: let each Claude account use its own session key (upstream #346)`
- [ ] **Step 2: 배치 D 전체 게이트.** `swift test` 전체 PASS.

## 배치 F — SP2 이월 + 마감

### Task 12: 메뉴바 한도의 다중 계정 소스 + 실측 (업스트림 커밋 없음)

**Files:**
- Modify: `Core/UsageStore.swift`(`menuLimitParts` 의 Claude 소스를 SP2 치환분 `limits?.fiveHour` 에서 업스트림 `menuClaudeAccount`(#327 이 도입, `trackedClaudeAccount` 기반)로 복원 — `git show b32717f` 의 해당 헝크와 `git show e5b4800` 의 `menuClaudeAccount` 정의를 대조해 이식)
- Test: `UsageStoreTests`(기존 `menuLimitParts`·`testMenuLinesAllCombinations` 계열이 회귀 가드 — 다중 계정 케이스 1개 추가)

**Interfaces:**
- Consumes: Task 9 `trackedClaudeAccount`·`menuClaudeAccount`.

- [ ] **Step 1: 테스트 먼저(RED).**

```swift
/// 메뉴바 한도는 추적(기본) 계정을 따른다 — 단 컴팩트 게이트(오늘 사용>0)는 그대로다.
func testMenuLimitFollowsTheTrackedAccountButKeepsTheTodayGate() async {
    // 계정 2개(기본·추가) 픽스처: ① 기본 계정 한도가 메뉴 파트에 반영 ② 오늘 토큰 0 이면
    // 한도가 메뉴에 안 나온다(기존 게이트) — 추가 계정 한도는 메뉴에 새지 않는다.
}
```

- [ ] **Step 2: 소스 복원 → GREEN** — MESSAGE=`feat(menubar): source the limit percentage from the tracked Claude account`
- [ ] **Step 3: SP2 이월 minor 편승 정리(지나가는 파일만).** 이번 포팅이 건드린 파일 안의 4건 — ① `LocalUsageReader` Grok no-ticks 행에 `costUnavailable: true`(+낡은 "추정 대신 0" 주석 수정) ② `UsageStore:69` 낡은 주석 ③ `prevMonthDaily` 중복 대입 제거 ④ 죽은 코드(`limitColor`·`UsageCost.explanation()`·`cost*Hint`·`ModelPricing.cost()`)는 **이번 포팅 파일에 겹칠 때만** 삭제, 아니면 장부에 남긴다. 각각 1줄 커밋 또는 이 태스크 커밋에 포함.
- [ ] **Step 4: 전체 마감 게이트.** `swift test` 전체 PASS + `./scripts/test-gate.sh` 커버리지 게이트 PASS.
- [ ] **Step 5: Dev 빌드 실측.** `PTB_DEV=1 PTB_INSTALL=1 scripts/build-app.sh` → 체크리스트: ① 계정 라벨(email·org) 표시 ② 세션 키 입력 → 자동 폴 2회에서 한도 갱신·Keychain 프롬프트 0회 ③ 계정 탭 전환 ④ 메뉴바 % 가 기본 계정 추종(사용자 실물 확인 요청 — 실 세션 키는 사용자만 넣는다, 세션 키 값은 대화에 옮기지 않는다).
- [ ] **마감:** 최종 리뷰(신선 컨텍스트, 최상위 모델) → Critical/Important 1회 수정 패스 → 머지는 사용자 확인.

## 자체 점검 메모 (스펙 대비)

- 스펙 배치 매핑: E(선행)→T1, A→T2–5, B→T6–7, C→T8, D→T9–11, F→T12. 11커밋 + 이월 1건 전부 소화.
- 제외 3건(#334·비-Claude 프로바이더·docs 커밋)은 스펙 §제외 그대로 — 계획에 태스크 없음이 의도.
- Review Focus 5건 모두 담당 태스크에 테스트 단계 존재(T1·T6·T9×2·T10).
- `probe-session-key.swift` 는 업스트림에 실존하지 않음을 확인(T6 Step 4) — 스펙의 해당 문장은 실행 중 장부로 정정.
- 업스트림 대형 테스트 3파일(1,925·555·319줄)의 선별 기준은 각 태스크 Files 절에 명시(버릴 의존 목록).
