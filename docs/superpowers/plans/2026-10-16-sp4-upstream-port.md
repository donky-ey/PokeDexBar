# SP4 Upstream Port Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 업스트림 잔여 변경 중 사용자가 확정한 26커밋(+#373)과 업스트림 열린 이슈 2건(#337·#443)을 배치 8개(A~H)로 포크에 이식한다.

**Architecture:** SP1~SP3 과 같은 커밋 단위 재구현 포팅이다. 다만 **배치마다 `origin/main` 에서 브랜치를 새로 따고 PR 을 하나씩 연다**. 실행 순서는 A → D → G → B → C → E → F → H. 다음 배치가 열린 PR 과 파일이나 의존이 겹치면 거기서 멈추고 보고한다. 업스트림 커밋이 없는 항목(이슈 #337·#443, 포크 결함)은 미머지 업스트림 PR 을 참고 자료로만 쓰고 포크 테스트로 처음부터 검증한다.

**Tech Stack:** Swift 6 / SwiftPM, XCTest, bash(`scripts/`). 업스트림 소스는 `git show <hash>`.

**Spec:** `docs/superpowers/specs/2026-10-16-sp4-upstream-port-design.md`

## Global Constraints

- 브랜치: 배치마다 `origin/main` 최신에서 `port/sp4-<배치 문자>-<slug>`. 첫 PR(배치 A)에 spec·plan 커밋을 같이 싣는다.
- 커밋·PR 제목·본문은 영어. 포팅 커밋은 `(upstream #NNN)`, 이슈 수정은 `(upstream issue #NNN)`. `Co-Authored-By` 트레일러와 "Generated with Claude Code" 서명은 넣지 않는다.
- push 와 PR 생성까지. **main 직접 push·머지 금지.** 리뷰 수정은 같은 브랜치에 커밋을 더한다.
- `Localization` 헝크는 **ko/en/ja 만**.
- 포크에 없는 파일(Antigravity·Cursor API·Copilot·Kiro·Pi·omp·Aside·Kimi·SaveTransfer·SaveSnapshots)의 헝크는 버린다. CompanionStore 는 PlayerStore 로 바꾼다.
- 포크 규칙이 우선한다: 메뉴바 idle 규율(트랜잭션·diff-gate·0.4s 하한·tolerance 0.5), 펫 `frameFloor = 0`, 자동 폴의 Keychain 무접촉, 테스트의 실 저장소 무접촉.
- 외부 포맷(#318 `cost-state`, #363 `session_message`, #337 JSONL 경계, #443 미러 행)은 업스트림 writer 나 실파일로 계약을 확정한 뒤 파서를 쓴다.
- 배치 경계마다 `./scripts/test-gate.sh`. 불안정 테스트 `SessionKeySettingsRenderingTests:46` 이 깨지면 한 번 다시 돌리고 PR 에 적는다.
- `git add` 는 경로를 명시한다(미추적 로컬 파일 `AGENTS.md` 등 보호). `*.rej`·`*.orig` 는 파일별 수동 처리 후에만 지운다.

## 공통 포팅 절차 P

```bash
git show <HASH>                                                   # P1. 전체 정독 — 버릴 헝크를 정한다
git show <HASH> -- 'Tests/*' | sed 's|PokeTokenBar|PokeDexBar|g' | git apply --reject   # P2. 테스트 선이식
swift test --filter <TESTCLASS> 2>&1 | grep -E "error|failed"       # P3. RED
git show <HASH> -- 'Sources/*' | sed 's|PokeTokenBar|PokeDexBar|g' | git apply --reject # P4. 소스, 리젝트는 수동
swift test --filter <TESTCLASS>                                     # P5. GREEN
git add <paths> && git commit -m "<MESSAGE>"                        # P6
```

## Review Focus

1. **Dev 빌드 세이브는 그대로여야 한다** — 배치 A 가 비번들 실행의 저장소를 임시 폴더로 돌린 뒤에도, 번들 앱(정식 `PokeDexBar`·Dev `PokeDexBarDev`)은 예전 경로를 그대로 써야 한다. → Task A1 Step 1 의 번들 대조군.
2. **단일 인스턴스 가드가 유일한 인스턴스를 죽이면 안 된다** — 시작 시각이 없거나 같으면 아무것도 하지 않는다(아이콘 0개보다 2개가 낫다). → Task D1 Step 1.
3. **증분 파싱은 합계를 바꾸면 안 된다** — 파일이 줄거나(잘림·재작성), 같은 크기로 바뀌거나, 마지막 줄이 반쯤 쓰였을 때도 전체 파싱과 같은 entries 가 나와야 한다. → Task B1 Step 1.
4. **프로바이더별 원장은 이중 적립을 만들면 안 된다** — 한 프로바이더가 사라졌다가 같은 날 돌아올 때, 날짜가 바뀌고 낡은 스냅숏이 올 때. → Task C1 Step 1.
5. **바깥 클릭 모니터는 팝오버·플로팅 펫 안의 클릭으로 닫히면 안 된다**, 시작·정지는 멱등이어야 한다. → Task E1 Step 1.

---

## 배치 A — 테스트 격리·가드 (`port/sp4-a-test-isolation`)

### Task A1: 앱 저장소 격리 — #359 와 부류 스윕 (`d6d24a0`)

부류: 비번들 실행(`swift test`·로우 바이너리)이 실 `~/Library/Application Support/PokeDexBar/` 를 읽고 쓴다. `AppEnv.storageName` 은 비번들에서 `"PokeDexBar"` 라 설치본과 같다. 스윕 결과(기준 `f75a25a`):

| 저장소 | 기본 경로 | 비번들 실행에서 |
|---|---|---|
| `LocalUsageCache` `usage-cache.json` | `LocalUsageCache.swift:123-128` | **읽고 쓴다**(#359 그 자체 — 기본 프로바이더가 `.shared` 를 쓴다) |
| 스프라이트 캐시 `sprites/` | `SpriteLoader.swift:30,146` | **쓴다** — `FormTests.swift:1149,1167` 이 가짜 GIF 를 실 캐시에 쓴다 |
| `PokeAPIClient` `base-index.json`·`species-profiles/` | `PokeAPIClient.swift:92,264` | 부화 경로가 기본 클라이언트를 타면 읽고 쓴다 |
| `PlayerStore` `player-state.json` | `PlayerStore.swift:49` | 테스트는 전부 경로를 주입한다 — 지금은 안전하지만 막는 장치가 없다 |
| `WeatherClient` `weather.json` | `WeatherClient.swift:22` | 같은 상태(주입 의존) |
| `SessionKeyStore` | `SessionKeyLimitsProvider.swift:85-91` | 이미 임시 폴더로 갈라져 있다(선례) |
| 패리티 스냅숏 | `UsageStore.swift:1769-1771` | `isBundledApp` 가드로 막혀 있다 |
| 로그류(`AppLog`·`Breadcrumbs`·`LastCrash`) | `~/Library/Logs` | 쓰기는 이미 가드되어 있다 — 범위 밖 |

수정은 저장소마다 게이트를 다는 대신(업스트림 `persistsToUserLocation` 방식) **뿌리에서 막는다**. `AppEnv.supportDirectory()` 가 비번들 실행이면 프로세스마다 임시 폴더를 돌려주고, App Support 경로는 모두 그것만 거치게 한다. 포크 선례(`SessionKeyStore`·`Breadcrumbs`·`LastCrash` 의 임시 경로)와 같은 방향이고, 앞으로 생길 저장소도 구조적으로 격리된다.

**Files:**
- Modify: `Sources/PokeDexBar/Core/AppEnv.swift`, `Core/LocalUsageCache.swift`, `Core/PokeAPIClient.swift`, `UI/SpriteLoader.swift`, `Core/UsageStore.swift`(패리티 2줄), `Core/SessionKeyLimitsProvider.swift`, `Core/WeatherClient.swift`, `CLAUDE.md`(규칙 확장)
- Create: `Tests/PokeDexBarTests/AppStorageIsolationTests.swift`
- Modify: `Tests/PokeDexBarTests/LocalUsageCacheTests.swift`, `Tests/PokeDexBarTests/SessionKeyLimitsTests.swift`

**Interfaces:**
- Produces: `AppEnv.userSupportDirectory: URL`(실 위치 — 번들 앱만 쓴다. 디렉터리를 만들지 않는다), `AppEnv.supportDirectoryURL(isBundledApp: Bool = AppEnv.isBundledApp) -> URL`(순수, 만들지 않음), `AppEnv.supportDirectory(isBundledApp: Bool = AppEnv.isBundledApp) -> URL`(위 경로 + 생성). 비번들 경로는 `FileManager.default.temporaryDirectory/PokeDexBar-<pid>`.
- 시험용 노출: `LocalUsageCache.fileURL`(`nonisolated let`), `WeatherClient.fileURL`(internal), `PokeAPIClient.baseIndexFile`(internal static).

- [ ] **Step 1: 실패 테스트 — `AppStorageIsolationTests`**
  - `testANonBundledRunGetsAnIsolatedSupportDirectory`: `supportDirectoryURL(isBundledApp: false)` 와 기본 호출 `supportDirectoryURL()`(xctest = 트리거 브랜치) 모두 `userSupportDirectory` 아래가 아니다. 대조군: `supportDirectoryURL(isBundledApp: true) == userSupportDirectory`.
  - `testEveryDefaultStorePathStaysOutsideTheUserLocation`: `LocalUsageCache().fileURL`, `PlayerStore.defaultURL()`, `SpriteLoader.cacheDir`, `WeatherClient().fileURL`, `PokeAPIClient.baseIndexFile`, `SessionKeyStore().fileURL` 가 모두 `userSupportDirectory.path` 접두가 아니다.
  - `testNoAppSupportPathIsComposedOutsideAppEnv`: `Sources/` 의 `.swift` 를 **주석을 걷어낸 뒤** 훑어 `applicationSupportDirectory` 가 `AppEnv.swift` 밖에 없음을 단언한다(통짜 `contains` 는 주석에 걸려 무력해진다 — CLAUDE.md backfill 가드 교훈).
- [ ] **Step 2: RED 확인** — `swift test --filter AppStorageIsolationTests` 가 세 테스트 모두 실패한다(경로 단언으로만 실패 — 이 단계에서는 실 캐시를 스캔하는 테스트를 돌리지 않는다).
- [ ] **Step 3: 구현** — `AppEnv` 세 멤버를 추가한다. `LocalUsageCache.defaultFileURL`·`PokeAPIClient.baseIndexFile`·`SpriteLoader.cacheDir`·패리티 스냅숏을 `supportDirectory()` 로 바꾸고, `SessionKeyStore.defaultDirectory(isBundledApp:)` 는 `AppEnv.supportDirectory(isBundledApp:)` 로 합친다(중복 경로 삭제).
- [ ] **Step 4: 업스트림 회귀 테스트 이식(포크 모양)** — `LocalUsageCacheTests` 에 `testDefaultPathCacheNeverRewritesTheUserFile`(기본 경로 캐시로 픽스처 스캔 → 결과 1건, 실 `usage-cache.json` 의 mtime 이 **첫 스캔 전 표본**과 같다)와 `testInjectedPathCacheStillPersists`(주입 경로는 여전히 파일을 쓴다). `SessionKeyLimitsTests:535-554` 의 비교 기준을 `AppEnv.supportDirectory()` 에서 `AppEnv.userSupportDirectory` 로 바꾼다(지금은 xctest 에서 둘이 같은 실 폴더라 우연히 맞던 단언).
- [ ] **Step 5: GREEN + 결함 주입** — 필터 테스트가 통과한다. `supportDirectoryURL` 의 비번들 분기를 잠시 되돌리면 세 테스트가 각각 깨지는지 확인한다(가드가 발동하는지 센다).
- [ ] **Step 6: CLAUDE.md 규칙 확장** — "테스트가 실 앱의 자격증명 저장소를 공유하게 두지 마라" 를 **앱 저장소 전반**으로 넓힌다: 뿌리(`AppEnv.supportDirectory`)와 가드(`AppStorageIsolationTests` 세 개)를 적는다.
- [ ] **Step 7: 커밋** — `fix: isolate every app-support store from test runs (upstream #359)`

### Task A2: 자릿수 묶음 단언의 로케일 고정 (`f9ae41d`, #166)

**Files:** Modify `Core/TokenFormatter.swift:21-26`, `Tests/PokeDexBarTests/LocalUsageCacheTests.swift:761`

- [ ] **Step 1:** `testFormatterEdges` 를 `grouped(253_412_890, locale: Locale(identifier: "en_US")) == "253,412,890"` 와 `es_ES` → `"253.412.890"` 로 바꾼다(RED: 인자가 없어 컴파일 실패).
- [ ] **Step 2:** `grouped(_ value: Int, locale: Locale = .current) -> String`. 기본값이라 프로덕션 동작은 같다. GREEN.
- [ ] **Step 3: 커밋** — `test: pin the locale when asserting grouped numbers (upstream #166)`

### Task A3: UI 한글 리터럴 가드 (`a6ed409` 의 테스트만, #222)

**Files:** Create `Tests/PokeDexBarTests/LocalizedUILiteralTests.swift`

- [ ] **Step 1:** 업스트림 테스트를 이식하되 스캔 대상을 `Sources/PokeDexBar/UI/` 와 `Sources/PokeDexBar/PokeDexBarApp.swift` 로 한다(포크는 앱 진입 파일에도 UI 문구가 있다). Core·Player 는 언어별 데이터 테이블이라 제외한다.
- [ ] **Step 2:** 지금 상태로 통과한다(기준 시점 0건). 결함 주입: UI 파일 하나에 `Text("테스트")` 를 잠시 넣으면 실패하는지 확인한다.
- [ ] **Step 3: 커밋** — `test: guard UI sources against Hangul string literals (upstream #222)`. Antigravity 안내 헝크는 버린다.

**배치 A 종료:** `./scripts/test-gate.sh` 실행 후 실 `usage-cache.json` 의 mtime 이 스위트 전후로 같은지 확인한다 → push → PR.

---

## 배치 D — 앱 수명주기 (`port/sp4-d-app-lifecycle`)

업스트림 순서대로 진행한다. `PopoverView`·`SettingsView`·`Localization` 은 #311 만 건드린다.

### Task D1: 두 번째 인스턴스 방지 (`de0ddd8`, #163)

**Files:** Create `Core/SingleInstance.swift`, `Tests/PokeDexBarTests/SingleInstanceTests.swift`. Modify `Core/AppLog.swift`(`flush()`), `PokeDexBarApp.swift:35-41`(`CrashReporter.install` **앞**), `scripts/e2e.sh`(인스턴스 1개 단언).

**Interfaces:** Produces `SingleInstance.shouldYield(myStartTime: Date?, otherStartTimes: [Date?]) -> Bool`(순수 판정), `SingleInstance.shouldYieldToRunningInstance() -> Bool`(커널 `p_starttime` 비교, 나중 인스턴스가 양보), `AppLog.flush()`.

- [ ] **Step 1: 절차 P** — HASH=`de0ddd8`, TESTCLASS=`SingleInstanceTests`. 업스트림 테스트에 시작 시각 없음·동일 → 양보하지 않음 대조군이 있는지 확인하고, 없으면 추가한다(Review Focus 2).
- [ ] **Step 2:** 포크는 레거시 로그인 항목 마이그레이션이 없다 — 그 경로 헝크는 버리고, 토글 경로(`LoginItem.setEnabled`)만 가드가 덮는지 주석으로 남긴다.
- [ ] **Step 3: 커밋** — `fix: stop a second instance from appearing when the login agent is registered (upstream #163)`

### Task D2: willTerminate 경로 AppLog 플러시 (`052eacf`, #174/#180)

**Files:** Modify `Core/AppLog.swift`, `Core/CrashReporter.swift:104-107`, `PokeDexBarApp.swift`. Create `Tests/PokeDexBarTests/AppLogTests.swift`(포크에 있으면 헝크만).

- [ ] **Step 1: 절차 P** — HASH=`052eacf`, TESTCLASS=`AppLogTests`. 포크 `AppLog` 의 `isBundledApp` 쓰기 가드(`:26,:49`)는 유지한다 — 테스트가 실 로그를 쓰면 안 된다.
- [ ] **Step 2: 커밋** — `fix: flush AppLog on the willTerminate exit path (upstream #174)`

### Task D3: 업데이트 루프가 PID 를 기다림 (`566818a`, #175/#186)

**Files:** Modify `Core/UpdateChecker.swift:122-130`, `Tests/PokeDexBarTests/UpdateCheckerTests.swift`

- [ ] **Step 1: 절차 P** — HASH=`566818a`, TESTCLASS=`UpdateCheckerTests`. 스크립트 문자열 단언(`pgrep -x` 가 없고 `kill -0 <pid>` 대기)이 테스트다.
- [ ] **Step 2: 커밋** — `fix: wait for the app's PID instead of its name in the update loop (upstream #175)`

### Task D4: 건너뛴 릴리스를 설정에 표시 (`1c695c7`, #311)

**Files:** Modify `Core/UpdateChecker.swift:46-58`, `UI/SettingsView.swift:337-342`, `UI/PopoverView.swift:150`, `Core/Localization.swift`(ko/en/ja), `Tests/PokeDexBarTests/UpdateCheckerTests.swift`

- [ ] **Step 1: 절차 P** — HASH=`1c695c7`, TESTCLASS=`UpdateCheckerTests`. 업스트림 추가 언어 문자열은 버린다. "나중에" 버튼의 실제 의미(영구 건너뛰기)를 업스트림 문구로 맞춘다.
- [ ] **Step 2: 커밋** — `fix: show a skipped release in Settings instead of "up to date" (upstream #311)`

### Task D5: 검증된 릴리스 뒤에만 쿨다운 기록 (`a2ec364`, #321)

**Files:** Modify `Core/UpdateChecker.swift:28-45`, `Tests/PokeDexBarTests/UpdateCheckerTests.swift`. **버림:** `default.profraw`.

- [ ] **Step 1: 절차 P** — HASH=`a2ec364`, TESTCLASS=`UpdateCheckerTests`. 트리거 브랜치: fetch 실패 직후 재호출이 쿨다운에 막히지 않는다, 태그가 버전 형식이 아니면 available 을 세우지 않는다.
- [ ] **Step 2: 커밋** — `fix: stamp the update-check cooldown only after a validated release (upstream #321)`

**배치 D 종료:** test-gate → push → PR. 스크린샷(설정·팝오버 업데이트 배너)은 릴리스 때 다시 만든다고 PR 에 적는다.

---

## 배치 G — 빌드·배포 (`port/sp4-g-universal-build`)

### Task G1: 유니버설 바이너리 (`498bdbc`, #400)

**Files:** Modify `scripts/build-app.sh:27-51`, `scripts/release.sh`(조립 후 `lipo -verify_arch arm64 x86_64` 하드 게이트), `RELEASE.md`

- [ ] **Step 1:** 업스트림처럼 아키텍처별 `swift build -c release --arch <a>` 후 `lipo -create`. `PTB_NATIVE_ARCH_ONLY=1` 로 로컬 단일 아키텍처 빌드를 허용한다. 리소스 번들은 슬라이스별 bin 경로에서 복사한다(`--show-bin-path`). 디버그(`PTB_DEV`) 경로도 확인한다.
- [ ] **Step 2: 검증** — `./scripts/build-app.sh` 후 `lipo -archs "build/PokeDexBar.app/Contents/MacOS/PokeDexBar"` 가 `x86_64 arm64` 를 출력한다. 앱이 이 기기(arm64)에서 뜨는지, `arch -x86_64` 실행이 가능하면 그것도 확인한다. Intel 실기기 검증은 불가 → PR 에 `lipo -archs` 결과로 대신했다고 적는다.
- [ ] **Step 3: 커밋** — `fix: ship a universal (arm64 + x86_64) app binary (upstream #400)`

### Task G2: 릴리스 노트 필수화 (`5e08e6f` 의 노트 부분만, #296)

**Files:** Modify `scripts/release.sh:143-150`, `RELEASE.md`

- [ ] **Step 1:** `PTB_NOTES_FILE` 이 없거나 비었으면 **테스트 게이트 전에** 중단한다. 기여자 검증기·템플릿은 버린다(단일 메인테이너).
- [ ] **Step 2: 검증** — `PTB_NOTES_FILE= ./scripts/release.sh --check-only` 류로 중단 메시지를 확인한다(실 릴리스 단계에 들어가지 않는 경로로).
- [ ] **Step 3: 커밋** — `fix: require release notes before the release starts (upstream #296)`

**배치 G 종료:** test-gate → push → PR. 본문에 "다음 릴리스 전에 머지 필요" 를 적는다.

---

## 배치 B — Claude 로그 스캔 성능·정확도 (`port/sp4-b-claude-scan`)

배치 A 의 `LocalUsageCache` 변경 위에 쌓인다 → **A 머지 뒤 착수**.

### Task B1: 활성 세션 파일 증분 파싱 (이슈 #337, 미머지 PR #338 참고)

**Files:** Modify `Core/LocalUsageCache.swift`(`Blob` 에 `offset: Int`, 덧붙은 꼬리만 파싱, 캐시 스키마 버전 증가), `Core/LocalUsageReader.swift:345-361`(`parseClaudeFile(_:fmt:from offset:) -> (entries, consumedOffset)` — `Data` 바이트 단위, 마지막 `\n` 까지만), `Core/Models.swift:462-480`(`ISO8601Parser` 공유 포매터, 잠금 — `LocalAdditionalUsageProvider.swift:473-499` 패턴). Test: `LocalUsageCacheTests`.

- [ ] **Step 1: 실패 테스트** — `testAppendedLinesAreParsedFromTheSavedOffset`(덧붙인 줄만 읽힘 — 파싱 호출 바이트 수로 관찰), `testHalfWrittenLastLineWaitsForItsNewline`, `testTruncatedFileIsReparsedFromStart`(크기 감소), `testSameSizeRewriteIsReparsed`(mtime 변화·크기 동일), `testIncrementalTotalsMatchAFullParse`(Review Focus 3 — 같은 파일 세트에서 증분과 전체 결과 동일).
- [ ] **Step 2:** 포크 다중 루트 `annotate` 경로에서 증분 entries 가 기존 blob entries 와 합쳐지고 파일 내 dedup 이 유지되는지 확인한다.
- [ ] **Step 3: 커밋** — `perf: parse growing Claude session logs incrementally (upstream issue #337)`

### Task B2: Claude 보고 비용 우선 (`8b2dd95`, #318) — **보류**

> 실행 결과(2026-10-16): 형식은 실 transcript 로 확정했으나, 원장이 `startTime` 이후 실행분만 담고 서브에이전트·
> 백그라운드 호출까지 포함해 업스트림의 "파일 전체 비례 배분"이 비용을 지우거나 이중으로 센다. 근거는 spec 배치 B
> 표. 포팅하지 않고 운영 총괄에게 결정을 올렸다. 다시 한다면 `startTime` 이후 항목만, 서브에이전트 귀속을 설계한 뒤.

- [ ] **Step 1:** 업스트림 writer(Claude Code 의 `cost-state` 기록)나 실 transcript 한 건으로 필드 이름·단위를 확정한다. 확정 못 하면 이 태스크는 보류하고 보고한다.
- [ ] **Step 2: 절차 P** — HASH=`8b2dd95`. 캐시 스키마 증가는 B1 과 한 번으로 합친다. 포크된 세션 재생 턴의 비용 몫 처리(과소집계 위험)를 테스트로 고정한다.
- [ ] **Step 3: 커밋** — `fix(claude): prefer reported cost-state over price-table estimates (upstream #318)`

### Task B3: 0토큰 synthetic 항목 제외 — 리더 (`a910767`, #333)

- [ ] 리더(`LocalUsageReader.swift:1483` 부근)에 `total > 0` 필터. 테스트: 0토큰 항목이 블록 시작·분당 토큰·`activeBlock` 에 영향 없음. 커밋 `fix: hide zero-token synthetic activity from blocks (upstream #333)`.

### Task B4: Sonnet 5.5 캐시 읽기 가격 (`dc6de41` 가격 부분)

- [ ] 1차 가격 페이지로 값을 확인한다. 업스트림($0.10)과 같으면 `ModelPricing.swift:33` 과 주석·테스트를 고친다. 다르면 포크 값을 유지하고 PR 에 근거를 적는다. 커밋 `fix: correct Sonnet 5.5 cache-read pricing (upstream dc6de41)`.

---

## 배치 C — 진행 원장 → OpenCode v2 → 미러 제거 (`port/sp4-c-opencode-ledger`)

**착수 직전 운영 총괄에게 SendMessage 로 한 줄 알린다**(#143 이 게임 레인 파일 `PlayerStore` 를 고친다).

### Task C1: 프로바이더별 진행 원장 (`c1a5e2f`, #143)

**Files:** `Player/PlayerStore.swift:98-124`, `Player/PlayerState.swift`(필드·디코드·`sanitized`), `Core/UsageStore.swift`(`todayTokensByProvider: [String: Int]`), `PokeDexBarApp.swift:195-198`, `CLAUDE.md` §상태 파일 분류(새 로컬 장부 필드).

**Interfaces:** Produces `PlayerStore.update(todayTokensByProvider: [String: Int], todayDate: String, hasUsageData: Bool)`.

- [ ] **Step 1: 실패 테스트** — 한 프로바이더 하락 + 다른 프로바이더 증가 → 증가분 적립(트리거 브랜치 단독), 프로바이더가 사라졌다 같은 날 복귀 → 이중 적립 없음, 날짜 변경 후 낡은 스냅숏 → 적립 없음(Review Focus 4), 옛 세이브(합산 장부만 있음) 로드 → 첫 갱신이 기준선 역할.
- [ ] **Step 2: 절차 P** — HASH=`c1a5e2f`. SaveTransfer 헝크 버림. 새 필드는 관대 디코딩 + `sanitized` 범위 검증(CLAUDE.md 신뢰경계 규칙).
- [ ] **Step 3: 커밋** — `fix: keep progress moving when one provider's daily total drops (upstream #143)`

### Task C2: OpenCode v2 읽기 (`3ea40af`, #363)

- [ ] **Step 1:** OpenCode v2 writer 의 `session_message` 스키마를 업스트림 OpenCode 소스로 확정하고, 픽스처는 그 스키마로 만든다.
- [ ] **Step 2: 절차 P** — HASH=`3ea40af`, TESTCLASS=`LocalAdditionalUsageTests`. 커밋 `fix: read OpenCode v2 session messages (upstream #363)`.

### Task C3: claude-code 미러 행 건너뛰기 (이슈 #443, Q3 확정 (a))

- [ ] **Step 1: 실패 테스트** — `providerID == "claude-code"` 행은 OpenCode 합계에서 빠진다, 대조군 `providerID == "anthropic"` 은 남는다(v1·v2 테이블 둘 다).
- [ ] **Step 2:** `LocalAdditionalUsageProvider` 의 OpenCode 파서 안에서만 거른다(확장 규약 — 프로바이더 간 결합 금지). README(en/ko/ja)에 `CLAUDE_CODE_SKIP_PROMPT_HISTORY=1` 이면 그 사용량이 빠진다고 적는다.
- [ ] **Step 3: 커밋** — `fix(opencode): skip claude-code mirror rows already counted by Claude Code (upstream issue #443)`

---

## 배치 E — 메뉴바·팝오버 상호작용·펫 (`port/sp4-e-menubar`)

순서: E1 → E2 → E3 → E4 → E5 → E6. 메뉴바 실측은 설치된 primary 앱 교체로만 한다.

### Task E1: 바깥 클릭 모니터 (`2577c7a` #154 → `12d4218` #168/#172)

- [ ] **Step 1: 실패 테스트** — 모니터 start 두 번 → 등록 1개, stop 두 번 → 안전, 팝오버·펫 창 안 클릭은 닫지 않음(Review Focus 5).
- [ ] **Step 2:** 두 커밋을 최종 형태로 한 번에 이식한다(`popoverDidShow` 에서 시작, `popoverDidClose` 에서 정지). 커밋 두 개로 남긴다: `fix: close the popover when another menu bar popup opens (upstream #154)`, `fix: make the popover outside-click monitor idempotent (upstream #168)`.

### Task E2: 메뉴바 우클릭 메뉴 (`be9cbc7`, #373)

- [ ] **Step 1: 절차 P** — HASH=`be9cbc7`. 신설 `UI/StatusItemMenu.swift`. 기존 문자열 재사용(`Localization.swift:566,753,755,762,883-884`). `showPopover` 분리 시 포크의 공개 호출 유지. 커밋 `feat(menubar): add a right-click menu to the menu bar item (upstream #373)`.

### Task E3: GIF 하한을 프레임 건너뛰기로 (`d6fb966` 의 `capFrameRate` 만, #212)

- [ ] **Step 1: 실패 테스트** — `GIFDecoder.capFrameRate(frames, floor: 0.4)` 가 총 재생 시간을 원본과 같게 유지하고(±한 프레임), 모든 지연이 ≥ 0.4.
- [ ] **Step 2:** `PokeDexBarApp.swift:275-277` 의 `max(0.4, $0.delay)` 를 대체한다. 프리셋·tolerance 헝크는 버린다. 실물 확인 후 커밋 `fix(menubar): keep GIF speed when capping the frame rate (upstream #212)`.

### Task E4: 메뉴바 저전력 전환 감지 (포크 결함)

- [ ] AppDelegate 에 `NSProcessInfoPowerStateDidChange` 옵저버 → `ensureMenuAnimation()`. 메뉴 애니메이션 키(`:235`)에 저전력 상태를 포함한다. 테스트: 키가 저전력 여부로 달라진다(순수 함수). 커밋 `fix(menubar): pick up Low Power Mode changes mid-session`.

### Task E5: 레이어로 프레임 교체 (`edc3b3c`, #255)

- [ ] **Step 1: 절차 P** — HASH=`edc3b3c`. diff-gate·`CATransaction` 규율이 그대로인지 확인한다. 고정 22×22 캔버스라 플레이스홀더 크기 로직은 한 번만 설정된다.
- [ ] **Step 2:** 설치된 primary 앱으로 전후 idle CPU 를 실측해 PR 에 적는다. CLAUDE.md 메뉴바 규칙 ① 문구를 레이어 방식으로 갱신한다. 커밋 `perf(menubar): swap sprite frames through a layer instead of button.image (upstream #255)`.

### Task E6: 펫 호버 툴팁 글자 (`73749c7`, #193)

- [ ] **Step 1: 절차 P** — HASH=`73749c7`. 커밋 `fix: prevent invisible text in the floating pet hover tooltip (upstream #193)`.

---

## 배치 F — 팝오버 레이아웃·현지화 (`port/sp4-f-popover-polish`)

핫스팟 4개를 모두 건드린다 → 게임 레인이 조용할 때 몰아서 한다.

### Task F1: 홈 탭 고정 높이 + 스크롤러 자리 (`d44329b`, #353)

- [ ] **Step 1: 절차 P** — HASH=`d44329b`. 높이는 다른 탭과 같은 320. 부화·공개 오버레이가 ScrollView 안에서 잘리지 않는지 스크린샷 생성기로 확인한다. 커밋 `fix(ui): give the Home tab a fixed height and reserve a scroller lane (upstream #353)`.

### Task F2: 선택 언어 일관성 — 공유 부분 (`2fab082`, #290 + SP3 이연 #7)

- [ ] **Step 1: 실패 테스트** — 세션 키 저장 실패 후 언어를 바꾸면 `sessionKeyError` 문구가 새 언어로 바뀐다(`sessionKeyFailure: (any Error)?` 저장 + computed — `limitTokenRefreshFailure` 와 같은 모양).
- [ ] **Step 2:** `PopoverView.swift:540-543` 토큰 라벨, `SettingsView.swift:107,110` 하드코딩, 빈 접근성 라벨 11곳을 `L` 로 옮긴다. 이름·도감·능력 헝크는 버린다. 커밋 `fix: keep errors and labels in the selected language (upstream #290)`.

### Task F3: 세션 키 설정 즉시 이동 (`b716054`)

- [ ] 애니메이션 없는 `scrollTo` + 포커스. 커밋 `fix: reveal session key settings without waiting for animation (upstream b716054)`.

---

## 배치 H — 문서·주석 (`port/sp4-h-docs`)

- [ ] **Task H1:** ccusage 주석 제거(`cb4fba7`, #256 — 위치는 spec 배치 H 표) + SP3 이연 #8 주석 교정. 커밋 `chore: drop stale upstream references from comments (upstream #256)`.
- [ ] **Task H2:** `CONTRIBUTING.{md,ko.md,ja.md}` 현행화(`8804232`, #364 — CI 는 `test-gate.sh`, 업스트림 링크는 포크 자료로). 커밋 `docs: align provider contribution guides with the current integration steps (upstream #364)`.
- [ ] **Task H3:** README(en/ko/ja)에 "claude.ai 채팅·Projects 사용량은 집계 대상이 아님" 명시(이슈 #439). 커밋 `docs: note that claude.ai chats and Projects are not counted (upstream issue #439)`.

## 배치 경계 체크리스트 (모든 PR)

- [ ] `./scripts/test-gate.sh` 요약 줄을 PR 본문에 인용한다.
- [ ] 핫스팟(`PopoverView`·`UsageStore`·`Localization`·`SettingsView`) 수정 여부를 PR 본문에 적는다.
- [ ] 버린 헝크와 그 이유를 커밋 본문에 적는다.
- [ ] UI 가 바뀌면 릴리스 때 스크린샷을 다시 만들어야 한다고 적는다(`feat:`+UI 는 신규 에셋 게이트).
