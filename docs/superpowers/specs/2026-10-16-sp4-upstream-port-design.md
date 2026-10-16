# SP4 — 업스트림 잔여 변경 트리아지·포팅 범위 제안 (설계)

2026-10-16 · 업스트림 동기화 레인 SP4 1단계(트리아지). SP1(정확도)·SP2(표시)·SP3(Claude 계정·한도)는
main 머지 완료(v1.19.0 `f75a25a`). 이 문서는 **분류와 범위 제안까지**다. 포팅 범위는 사용자가 확정하고,
확정되면 같은 브랜치에서 plan → 포팅을 이어 간다.

## 요약

- **대상**: `main..upstream/main` 의 머지 아닌 커밋 **191개**. 기준은 upstream `77f789d`(v2.5.6). 브리프 작성
  시점에는 183개였는데, `git fetch` 로 2.5.6 릴리스분 8개가 더해졌다. 머지 커밋은 0개다.
- **판정 분포**

  | 판정 | 개수 | 내역 |
  |---|---|---|
  | ① 이미 반영 | **56** | `(upstream #NNN)` 로 포팅된 것 50 + 포크에 같은 동작이 이미 있는 것 6 |
  | ② 해당 없음 | **87** | 게임 계층 44 · 릴리스·문서 16 · 비-Claude 한도 15 · 추가 언어 6 · 기타 4 · 한도-창 사탕 2 |
  | ③ 포팅 후보 | **26** | 상 4 · 중 12 · 하 10 (부분 포팅 6건 포함) |
  | ④ 사용자 결정 필요 | **22** | 신규 프로바이더 16 · 소형 UX 기능 4 · 세이브 백업 2 |

  이와 별도로 **업스트림 열린 이슈 3건**(#337·#443·#439)이 모두 포크에도 해당한다. 셋 다 업스트림
  main 에는 고친 커밋이 없다. #337·#443 은 열린 PR 이 있지만 아직 머지되지 않았고, #439 는 PR 도 없다.
- **제안 범위**: 후보 26건과 이슈 2건(#337·#443)을 의존 순서에 따라 **배치 A~H** 로 묶는다. 추천 실행
  순서는 **A → D → G → B → C → E → F → H** 다. 결정 항목 ④ 는 사용자가 고른 것만 배치 E(UX) 또는 별도
  SP 로 넣는다.

## 사용자 결정 필요 (범위 확정 전에 답이 필요한 것)

| # | 결정 | 선택지 | 추천 |
|---|---|---|---|
| **Q1** | **신규 사용량 프로바이더 7종**(커밋 16개, 아래 §④-1). Antigravity·Copilot·Kiro·Pi·omp·Aside·Kimi Code. 그중 Pi·omp·Aside·Kimi 는 #187 `CustomScanRoots`(프로바이더별 추가 스캔 폴더 설정 UI)에 기대고 있다 | (a) 계속 제외(SP1 결정 유지) (b) 사용자가 실제로 쓰는 CLI 만 (c) 전부 | **(a)**. 실제로 쓰는 CLI 가 있으면 (b) 로 그것만 넣는다. 프로바이더마다 "외부 로그 포맷은 상위 writer 로 검증" 규칙에 따른 검증 비용이 들고, 포크는 그 CLI 들의 실파일을 확보할 수 없다 |
| **Q2** | **소형 UX 기능 4건**(§④-2). 메뉴바 우클릭 메뉴 #373 · 펫 최대 크기 384px #267 · 넓은 스프라이트에 맞춰 메뉴바 폭 가변 #389 · 저전력 모드에서도 메뉴바 GIF 유지 #250 | 건별로 넣기/빼기 | #373 만 넣기(문자열이 이미 있어 비용이 작다). #389 는 포크가 일부러 고정 폭을 쓰고 있어(폭이 흔들리면 메뉴바가 떨린다) 빼기. #267·#250 은 에너지 규율과 맞바꾸는 문제라 원할 때만 |
| **Q3** | **#443 OpenCode 경유 Claude 사용량 중복 제거 방식**. 업스트림 PR #444 에서 메인테이너가 지적한 P2: `CLAUDE_CODE_SKIP_PROMPT_HISTORY=1` 이면 Claude 쪽 기록이 없어서, 무조건 건너뛰면 실제 사용량이 사라진다 | (a) `providerID=="claude-code"` 행을 무조건 건너뛰기 (b) 같은 턴이 Claude 로그에 있을 때만 건너뛰기(두 프로바이더가 서로 엮인다) | **(a)**. 그 환경변수 사용자는 드물고, (b) 는 "프로바이더마다 독립" 확장 규약을 깬다. 다만 (a) 의 손실 조건을 README 에 적는다 |
| **Q4** | **업스트림에서 머지되지 않은 이슈 수정을 SP4 에 넣을지**. #337(Claude 로그 증분 파싱, 미머지 PR #338 은 9-21 이후 방치되어 충돌 상태)과 #443(위 Q3) | (a) 넣는다(PR 을 참고만 하고 포크 모양으로 구현) (b) 업스트림 머지를 기다린다 | **(a)**. #337 은 포크 사용자(큰 히스토리)에게 지금 CPU·배터리 비용이다. 증거는 §이슈 |
| **Q5** | **세이브 자동 백업**(#330·#446, §④-3). 업스트림 `SaveSnapshots`(10개 보존·손상 복구·복원 UI) | (a) SP4 밖. 포크 고유 기능으로 따로 설계한다 (b) 지금 포팅 | **(a)**. 업스트림 구현이 `CompanionStore` 와 SaveTransfer 에 묶여 있고, 포크 세이브에는 `SaveSeal` 봉인이 있어 복원 경로가 봉인과 어떻게 맞물리는지부터 설계해야 한다 |

결정이 아니라 **확인 요청**인 것 두 가지:

- **배치 G(#400 유니버설 바이너리)는 릴리스 레인 파일**(`scripts/build-app.sh`·`release.sh`)을 고친다.
  운영 총괄이 릴리스 레인과 순서를 조율해야 한다. 지금 배포본은 Intel 에서 실행되지 않는데 README 는
  Intel 지원을 약속하고 있으니(§③ 배치 G), **다음 릴리스 전에 들어가야 한다**.
- **배치 C 의 #143 은 `Player/PlayerStore`·`PlayerState`(세이브 필드 추가)를 고친다.** 게임 레인 파일이므로
  게임 레인과 동시에 편집하지 않도록 순서를 잡아야 한다.

## 판정 기준

- **① 이미 반영**: main 커밋 메시지에 `(upstream #NNN)` 가 있거나(SP1~SP3 표와 대조했다), 포크 코드에 같은
  동작이 있다(file:line 으로 확인).
- **② 해당 없음**: 전제가 되는 기능이나 파일이 포크에 없다(업스트림 게임 계층, 한도-창 사탕, 추가 언어,
  비-Claude 한도). 또는 포크가 의도적으로 다르게 선택했다.
- **③ 포팅 후보**: 공유 코드(사용량·프로바이더·폴링·메뉴바·팝오버 셸·플로팅 펫·포맷터·가격표·빌드)의
  결함을 고치는 커밋. 포크에 결함이 실제로 있는지 코드로 확인했다.
- **④ 결정 필요**: 기능 추가이거나, 포크 규칙·선택과 맞바꾸는 것.
- 줄 번호는 이 브랜치의 기준 커밋 `f75a25a` 기준이다.

## ① 이미 반영 (56)

**SP1 포팅 (16)**: `a52c8c4` #137 · `ce0d8eb` #144 · `033853e` #145 · `b3910e3` #146 · `3f053d7` #176 ·
`eff18bb` #181 · `7a7149f` #184 · `b34673a` #252 · `5f1ef52` #262 · `232108c` #279 · `878a0be` #307 ·
`a94b3da` #360 · `5f6a4f0` #361 · `8c08e01` #369 · `906bbb9` #401 · `11eebe6` #402

**SP2 포팅 (23)**: `a1f736e` #150 · `f2fe5ac` #263 · `0912c68` #270 · `fd008e5` #286 · `69ff39b` #289 ·
`bb92bd2` #292 · `a8b3ba8` #293 · `2eec9af` #298 · `1ef1979` #304 · `29a4e2d` #309 · `78595ed` #332 ·
`142fa08` #348 · `68deb09` #349 · `832154a` #354 · `b32717f` #357 · `4cab9f0` #365 · `e21fb01` #367 ·
`5afeb2a` #368 · `a8dd806` #377 · `1e5603a` #384 · `0269dad` #395 · `231002d` #410 · `711fca7` #418

**SP3 포팅 (11)**: `40f4108` #199 · `3214f83` #227/#228 · `e81e620` #232 · `8953ea8` #241 · `7898065` #275 ·
`c9c016d` #280 · `3272509` #302 · `e5b4800` #327 · `e76a8e0` #344 · `eed5b73` #346 · `671c1ec` #355

**포크에 같은 동작이 이미 있음 (6)**

| 업스트림 | 내용 | 포크 근거 |
|---|---|---|
| `ad9e75e` #198 | fable-5 LiteLLM 가격 | `Core/ModelPricing.swift:45` 와 `:47` 이 업스트림 값과 완전히 같다(SP1 에서 선반영) |
| `1ff36e1` #243 | errSecParam 을 피하려고 Keychain 읽기를 둘로 나눔 | `Core/OAuthLimitsProvider.swift:346-447`. 속성만 열거한 뒤 계정마다 `kSecMatchLimitOne` 으로 읽는다(SP3 #232·#280 포팅에 흡수됨) |
| `1e69f3e` #148 | 사용량 폴 사이에 동반자가 바뀌면 메뉴바 즉시 갱신 | `PokeDexBarApp.swift:111-123` 의 `observePlayer`(포크 독자 구현) |
| `cbaaf60` #167/#171 | 잘릴 말풍선 문구 거부 | `UI/FloatingPetPanel.swift:122-180` 의 `SpeechBubbleLayout.wouldTruncate` |
| `bd0bba9` #194 | 메뉴바·팝오버 스프라이트 종횡비 유지 | `UI/CompanionView.swift:236,246` 의 `scaledToFit`, `PokeDexBarApp.swift:357-362` 의 `PixelScale.fittedRect`(고정 22×22 캔버스 — 방식은 다르고 결과는 같다) |
| `746d838` #356 | 이름에 맞는 한국어 조사 | `Core/Josa.swift:8-42`. 은/는과 숫자까지 다루는 상위 집합이고, `이(가)` 류 잔존은 0건이다 |

## ③ 포팅 후보 (26) — 배치 A~H

같은 파일 위에 쌓이는 커밋은 업스트림 순서를 지킨다(SP1~SP3 관례). 배치 순서는 의존 순서이고, 추천 실행
순서는 요약에 적었다.

### 배치 A — 테스트 격리·가드 (3) · 먼저

이후 배치의 테스트가 실 사용자 캐시를 건드리지 않게 하는 게이트다. SP3 의 #355 를 맨 앞에 둔 것과 같은 이유다.

| 업스트림 | 내용 | 포크 근거 | 우선 |
|---|---|---|---|
| `d6d24a0` #359 | **`swift test` 가 실 `usage-cache.json` 을 읽고 다시 쓰지 않게** | `Core/LocalUsageCache.swift:123-128` 의 `defaultFileURL` 이 실 `Application Support/PokeDexBar` 를 쓰고 디렉터리까지 만든다(`AppEnv.storageName` 은 비번들에서 `"PokeDexBar"`, `AppEnv.swift:44-46`). 읽기는 `:335`, 쓰기는 `:371` 이며 게이트가 없다. CLAUDE.md "테스트가 실 앱의 저장소를 공유하게 두지 마라"(세션 키 사고)와 **같은 부류**다. 포크 관례대로 `isBundledApp` 으로 가르거나 업스트림 `persistsToUserLocation` 을 도입한다 | **상** |
| `f9ae41d` #166 | 자릿수 묶음을 검증할 때 로케일 고정 | `Core/TokenFormatter.swift:22-26`. `LocalUsageCacheTests.swift:761` 이 쉼표를 하드코딩해서 지역 설정이 다른 기기에서는 실패한다 | 하 |
| `a6ed409` #222 (**가드만**) | UI 소스의 한글 문자열 리터럴을 잡는 `LocalizedUILiteralTests` | 지금 포크 UI 의 한글 리터럴은 0건이다(전수 스캔). 그 상태를 잠그는 값싼 가드다. Antigravity 안내 문구 헝크는 버린다 | 하 |

충돌: `LocalUsageCache`(배치 B 와 겹친다 → A 를 먼저). 핫스팟 없음.

### 배치 B — Claude 로그 스캔 성능(#337)·사용량 정확도 (3 + 이슈 1)

| 업스트림 | 내용 | 포크 근거 | 우선 |
|---|---|---|---|
| (이슈 #337, 미머지 PR #338 참고) | **활성 세션 파일 증분 파싱**: `Blob.offset` 을 두고, 덧붙은 꼬리만 바이트 단위로 파싱하고, 마지막 완결 줄에서 멈춘다. `ISO8601DateFormatter` 는 공유 인스턴스로 바꾼다 | §이슈 #337. 포크의 다중 루트 `annotate` 경로에 맞춰 이식해야 하고, 덧붙임·잘림·반쯤 쓰인 줄 테스트가 필요하다 | **상** |
| `8b2dd95` #318 | Claude 로그가 보고한 `cost-state` 를 가격표 추정보다 우선 | `Core/LocalUsageReader.swift:345-361` 에 `cost-state` 파싱이 없다. `Bucket.add` 는 이미 `explicitCost` 를 우선한다(`:68`). `claudeParserVersion` 캐시 스키마 증가는 #337 과 한 번에 올린다. **위험 두 가지**: ① 실 transcript 로 writer 를 확인하라(CLAUDE.md 외부 포맷 규칙) ② 포크된 세션의 재생 턴은 비례 몫의 비용을 받은 뒤 dedup 으로 사라지므로 세션 비용이 과소집계될 수 있다 | 중 |
| `a910767` #333 (**리더 부분**) | 토큰 0 인 synthetic 항목 제외 | 스토어 쪽은 이미 있다(`UsageStore.swift:1795-1802`). 리더(`LocalUsageReader.swift:1483`)에 `total > 0` 필터가 없어서, 0토큰 항목이 블록 시작을 앞당기고 분당 토큰을 낮추며 0토큰 `activeBlock` 을 남긴다(`UsageStore.swift:884-886`) | 하 |
| `dc6de41` (**가격 부분**) | Sonnet 5.5 캐시 읽기 $0.20 → $0.10 | `Core/ModelPricing.swift:33`. 포크 주석은 "09-29 확인 $0.20", 업스트림은 "10-16 확인 $0.10" 이다. **포팅 전에 1차 가격 페이지를 확인한다.** blob 이 원시 토큰을 저장하므로 캐시 증가는 필요 없다. 같은 커밋의 백업·폼·Antigravity 헝크는 버린다 | 중 |

충돌: `LocalUsageReader`·`LocalUsageCache`·`Models`·`ModelPricing`. 핫스팟 아님.

### 배치 C — 진행 원장 → OpenCode v2 → 미러 중복 제거 (2 + 이슈 1)

순서가 중요하다. **#443 은 합계를 낮추는 수정**이라, #143 없이 넣으면 그날 성장이 멈춘다.

| 업스트림 | 내용 | 포크 근거 | 우선 |
|---|---|---|---|
| `c1a5e2f` #143 | **프로바이더별 진행 원장**: 한 프로바이더의 일 합계가 줄거나 사라져도 다른 프로바이더 적립이 계속된다 | `Player/PlayerStore.swift:98-124` 가 합산 1개(`todayTokens > claimedTodayTokens`)로만 비교한다. 한 소스가 내려가면 **모든 프로바이더**의 지갑·EXP·알 진행이 그 고점을 다시 넘을 때까지 멈추고, 자정에 저절로 풀려서 아무도 모른다. `PlayerState`(필드·디코드·sanitize), `UsageStore`(`todayTokensByProvider`), `PokeDexBarApp.swift:195-198` 을 고친다. CLAUDE.md "상태 파일 분류"에 새 로컬 장부 필드를 추가해야 한다. SaveTransfer 헝크는 버린다(포크에 없음) | 중 |
| `3ea40af` #363 | **OpenCode v2 `session_message` 테이블 읽기** | `Core/LocalAdditionalUsageProvider.swift:227-243` 이 레거시 `message` 테이블만 읽는다. v2 사용자는 새 사용량이 0이다. writer 스키마를 먼저 확인한다 | **상** |
| (이슈 #443, 미머지 PR #444 참고) | OpenCode 의 `providerID=="claude-code"` 미러 행 건너뛰기 | §이슈 #443. #363 이 들어가야 v2 사용자에게도 완전히 해당된다. 방식은 Q3 | 중 |

충돌: `UsageStore`(**핫스팟**), `PlayerStore`·`PlayerState`(**게임 레인**), `LocalAdditionalUsageProvider`.

### 배치 D — 앱 수명주기: 단일 인스턴스·로그 플러시·업데이터 (5)

| 업스트림 | 내용 | 포크 근거 | 우선 |
|---|---|---|---|
| `de0ddd8` #163 | **두 번째 인스턴스 방지**(커널 `p_starttime` 순서로 나중 인스턴스가 양보하고, `CrashReporter.install` 보다 앞에 둔다) | 포크도 `SMAppService.agent` + plist `RunAtLoad`(`Core/LoginItem.swift:26-27`, `scripts/build-app.sh:91`)라서 **실행 중에 "로그인 시 실행"을 켜면 launchd 가 바이너리를 바로 하나 더 띄운다.** `PokeDexBarApp.swift:35-41` 에는 가드가 없다. 두 인스턴스가 모두 `player-state.json` 을 쓰고 마지막에 쓴 쪽이 이기므로 **진행이 유실될 수 있다** | **상** |
| `052eacf` #174/#180 | willTerminate 경로에서 AppLog 플러시 | `Core/AppLog.swift:45-68` 은 비동기이고 `flush` 가 없다. `CrashReporter.swift:104-107` 의 `markClean` 줄이 대개 유실된다. #163 의 양보 로그도 이게 있어야 남는다 → #163 과 한 쌍 | 하 |
| `566818a` #175/#186 | 업데이트 루프가 프로세스 이름이 아니라 PID 를 기다림 | `Core/UpdateChecker.swift:127` 의 `pgrep -x PokeDexBar`. 인스턴스가 중복되면 20초 정체와 번들 교체 경합이 생긴다 | 중 |
| `1c695c7` #311 | 건너뛴 릴리스를 설정에서 "최신"이 아니라 건너뜀으로 표시 | `UpdateChecker.swift:46-58` 이 건너뛴 정보를 잃어서 `SettingsView.swift:337-342` 가 "최신"이라고 말한다. 팝오버의 "나중에"(`PopoverView.swift:150`)는 실제로는 영구 건너뛰기다(`Localization.swift:1044`) | 중 |
| `a2ec364` #321 | 검증된 릴리스를 받은 뒤에만 쿨다운 기록 | `UpdateChecker.swift:32-33` 이 fetch **전에** 기록해서, 실패 한 번이면 30분간 재시도가 막힌다. 태그 검증도 없다(`:45`). 업스트림이 실수로 커밋한 `default.profraw` 는 가져오지 않는다 | 중 |

순서: #163 → #180 → #186 → #311 → #321(업스트림 순서). 충돌: `PokeDexBarApp.swift`·`AppLog`·`CrashReporter`·
`UpdateChecker`, **핫스팟 `PopoverView`·`SettingsView`·`Localization`**(#311 의 ko/en/ja 문구). e2e(`scripts/e2e.sh`)에
"인스턴스 1개" 단언을 더한다. launchd 경계는 단위 테스트가 닿지 않는 유일한 부분이다.

### 배치 E — 메뉴바·팝오버 상호작용·펫 (5 + 포크 결함 1)

| 업스트림 | 내용 | 포크 근거 | 우선 |
|---|---|---|---|
| `2577c7a` #154 | 다른 메뉴바 팝업이 열리면 팝오버 닫기 | 포크에는 바깥 클릭 모니터가 없다(`PokeDexBarApp.swift:80-81,409-421`). 모니터는 팝오버가 열려 있는 동안만 있으므로 idle 비용이 없다 | 중 |
| `12d4218` #168/#172 | 그 모니터의 시작·정지를 멱등으로, 시작은 `popoverDidShow` 에서 | #154 위. 최종 형태로 한 번에 이식한다 | 중 |
| `d6fb966` #212 (**`capFrameRate` 만**) | GIF 하한을 프레임 지연 늘리기가 아니라 **프레임 건너뛰기**로 | `PokeDexBarApp.swift:275-277` 의 `max(0.4, $0.delay)` 는 프레임마다 지연을 늘려서 **애니메이션 전체가 느려진다**(지연이 짧은 GIF 는 최대 약 8배 슬로모션). 프레임을 건너뛰면 0.4s 하한(포크 규칙)을 지키면서 원래 속도가 된다. 보이는 모양이 "부드러운 슬로모션"에서 "끊기지만 제 속도"로 바뀌므로 실물 확인 후 확정한다. **품질 프리셋·tolerance 0.1 헝크는 버린다**: 메뉴바 tolerance 0.5 규칙과 펫 `frameFloor = 0` 사용자 결정에 어긋난다 | 중 |
| (포크 결함, #250 에서 파생) | **메뉴바가 세션 중 저전력 모드 전환을 놓친다** | `PokeDexBarApp.swift:260` 은 프레임을 만들 때만 저전력 여부를 보고, AppDelegate 에 `NSProcessInfoPowerStateDidChange` 옵저버가 없다(펫에는 `FloatingPetPanel.swift:84-90` 에 있다). 옵저버를 달고 `ensureMenuAnimation` 을 부른다. Q2 의 #250 정책과 무관하게 필요하다 | 하 |
| `edc3b3c` #255 | 메뉴바 프레임을 `button.image` 대신 레이어로 교체 | `PokeDexBarApp.swift:281-323`. 포크의 diff-gate 와 `CATransaction` 규율을 **유지하는 구조**라 충돌이 없다. wakeup 은 그대로이고, 프레임당 메인 스레드 비용이 줄어든다(업스트림 실측 2.00ms → 0.27ms. 포크의 2줄 색 제목은 그 비용이 더 크다). CLAUDE.md 메뉴바 규칙 문구를 갱신해야 하고, **설치된 primary 앱으로 실측**해야 한다(보조 인스턴스로는 재현되지 않는다는 포크 기록) | 중 |
| `73749c7` #193 | 펫 호버 툴팁 글자가 안 보이는 문제 | `UI/FloatingPetPanel.swift:254-279`. `labelColor` 와 `windowBackgroundColor.cgColor` 가 서로 다른 appearance 에서 해석된다 | 중 |

순서: #154 → #172 → #212(capFrameRate) → 저전력 옵저버 → #255(같은 `setStatusImage`·`advanceMenu` 를 고치므로
마지막) → #193. Q2 에서 고른 항목은 #172 뒤에 붙인다(#373 은 `togglePopover` 를 `showPopover` 로 나누므로
모니터 작업 다음). 충돌: `PokeDexBarApp.swift`(전부), `SpriteAnimation`, `FloatingPetPanel`, CLAUDE.md. 핫스팟 없음.

### 배치 F — 팝오버 레이아웃·현지화 잔손질 (3)

| 업스트림 | 내용 | 포크 근거 | 우선 |
|---|---|---|---|
| `d44329b` #353 | 홈 탭 고정 높이 + 스크롤러 자리 확보 | 홈 탭(`PopoverView.swift:201-248`)에는 ScrollView 도 높이 상한도 없다. 다른 탭은 320 을 쓴다(`ShopTabView.swift:52`, `BagTabView.swift:29`). 다중 계정 한도에 포크의 추가 카드까지 쌓이면 팝오버가 화면을 넘을 수 있다. 부화·공개 오버레이가 ScrollView 안에서 잘리지 않는지 확인해야 한다 | 중 |
| `2fab082` #290 (**공유 부분만**) | 선택한 언어로 오류 문구와 라벨 일관 표시 | ① 오류: `sessionKeyError` 가 문자열로 저장된다(`UsageStore.swift:1411,1435,1479`). **SP3 이연 #7 과 같은 결함이다** → 여기서 같이 고친다. `PopoverView.swift:1113` 은 원시 오류를, `SettingsView.swift:178` 은 시스템 언어의 `localizedDescription` 을 보여 준다 ② 라벨: `PopoverView.swift:540-543` 의 "in/out/cache w/cache r", `SettingsView.swift:107,110` 의 "Web"/"♥ Sponsor" 하드코딩 ③ 빈 접근성 라벨 `Picker("")`/`Toggle("")` 11곳. 이름·도감·능력 라벨 헝크는 버린다(추가 언어·게임 UI) | 하~중 |
| `b716054` | 애니메이션을 기다리지 않고 세션 키 설정으로 이동 | `SettingsView.swift:65-69` 가 80ms 뒤 애니메이션 `scrollTo` 를 한다. 키 창이 아닌 호스트에서는 착지하지 못할 수 있다. 포크 `7c82285`(#275)의 후속, 한 줄 | 하 |

충돌: **핫스팟 4개 전부**(`PopoverView`·`SettingsView`·`Localization`·`UsageStore`). 게임 레인이 조용할 때 몰아서
하고, 스크린샷(`settings.png`·팝오버)을 다시 만든다.

### 배치 G — 빌드·배포 (3) · 릴리스 레인과 조율

| 업스트림 | 내용 | 포크 근거 | 우선 |
|---|---|---|---|
| `498bdbc` #400 | **유니버설(arm64 + x86_64) 바이너리** | `scripts/build-app.sh:27-33` 이 호스트 아키텍처 하나만 빌드하고 복사한다. README.md:360 은 "Apple Silicon or Intel" 을 약속한다 → Intel 사용자는 "bad CPU type" 으로 실행할 수 없다. 아키텍처별 빌드 + `lipo -create`/`-verify_arch` 게이트, 리소스 번들 경로(`:51`), `PTB_DEV` 경로를 고친다 | **상** |
| `5e08e6f` #296 (**노트 필수화만**) | `PTB_NOTES_FILE` 이 없으면 테스트 게이트 전에 중단 | `scripts/release.sh:143-150` 은 노트가 없으면 "Release v$VERSION" 로 넘어간다. 기여자 표기 검증기(업스트림 메인테이너 전용)는 버린다 | 하 |
| `fe31abf` #216 | swift.org/Homebrew Swift 6.3 툴체인 지원(UI 구조체 약 43개에 `@MainActor`, `xcrun llvm-cov` 의존 제거) | 로컬 Apple Swift 6.3.3 과 CI(Xcode 16)에서는 문제가 없다. UI 파일 약 15개를 훑으므로 모든 배치와 충돌한다 → **보류 권장**. 한다면 맨 마지막에 단독으로, `fix:`/`chore:` 로(`feat:` 이면 신규 에셋 게이트에 걸린다) | 하 |

### 배치 H — 문서·주석 (2 + 이슈 1)

| 업스트림 | 내용 | 포크 근거 | 우선 |
|---|---|---|---|
| `cb4fba7` #256 | 낡은 ccusage 언급 제거 | `BinaryLocator.swift:3`, `UsageStore.swift:639,692,748`, `LocalUsageProvider.swift:3`, `LocalUsageReader.swift:3`, `Models.swift:3,18,65,76,129`. **SP3 이연 #8**(업스트림 잔존 주석)과 같은 손질이라 한 커밋으로 묶는다 | 하 |
| `8804232` #364 | 프로바이더 기여 가이드 현행화 | `CONTRIBUTING.md:26` 은 "CI 가 `swift test` 실행"이라고 하지만 실제는 `test-gate.sh` 다. `:66` "두 곳만" 표현도 확인한다. 업스트림 이슈·`docs/reference` 링크는 포크의 자료로 바꾼다 | 하 |
| (이슈 #439) | README(en/ko/ja)에 "claude.ai 채팅·Projects 사용량은 집계 대상이 아님" 명시 | §이슈 #439 | 하 |

## ④ 결정 필요 (22)

### ④-1 신규 사용량 프로바이더 (16) → Q1

| 프로바이더 | 커밋 | 규모·의존 |
|---|---|---|
| Antigravity 사용량 | `42acf7d` #141 · `5bffcec` #151 · `7422507` #182 | 신설 리더 +842/+653/+495. 한도(#210 등)는 계속 제외 |
| GitHub Copilot CLI | `b71e9e3` #155 · `ad47d0d` #157/#160 | #160 은 Cursor·Copilot 의 증분 SQLite 스캔 공용화다. 포크 Cursor 는 이미 워터마크와 리셋 복구를 갖고 있어서(`LocalAdditionalUsageProvider.swift:309-329`) Copilot 없이는 이득이 작다 |
| Kiro CLI | `3a2945d` #170 · `8726908` #178/#179 · `ff54b44` #236/#238 · `cf91ddc` #383 | 4커밋 체인. #238 은 `UsageEnvironment` 를 고친다 |
| Pi Agent | `5d1ab04` #189 · `e6d99a8` #225 | **#187 `CustomScanRoots` 에 의존**. #225 의 모델별 분해 UI 는 Pi 전용 게이트다 |
| oh-my-pi (omp) | `b833f12` #214 · `ab6c768` #276 | #187 에 의존 |
| Aside | `5bd8d43` #283 | #187 에 의존 |
| Kimi Code | `40b506e` #403 | #187 에 의존 |
| (기반) 프로바이더별 추가 스캔 폴더 | `9bb7dee` #177/#187 | 약 960줄(설정 Advanced UI + 테스트 약 450줄) + 새 `assets/` 이미지(`feat`+UI 하드 게이트). SP1 에서 YAGNI 로 제외했다. Pi·omp·Aside·Kimi 중 하나라도 고르면 함께 들어오거나, 그 헝크를 걷어낸 채 이식해야 한다 |

확장 규약(CLAUDE.md)상 프로바이더 추가는 `UsageProvider` 구현체 하나와 등록 한 줄로 끝나는 구조라, **고르면
기술적 충돌은 작다.** 비용은 검증과 유지보수(외부 포맷이 바뀔 때마다 따라가야 한다)다.

### ④-2 소형 UX 기능 (4) → Q2

| 업스트림 | 내용 | 포크와의 관계 |
|---|---|---|
| `be9cbc7` #373 | 메뉴바 우클릭 메뉴(도감·설정·종료 등) | 문자열은 이미 있다(`Localization.swift:566,753,755,762,883-884`). 신설 `UI/StatusItemMenu.swift`. 도감 항목은 `nav.tab = .collection` 에 대응한다. SP2 에서 "원하면 별도 요청"으로 미뤘다 |
| `cd3125a` #267 | 펫 최대 크기 192 → 384px | 상수 하나(`UsageStore.swift:139` `48...192`, 슬라이더와 읽기 clamp 가 공유). 펫은 fps 상한이 없으므로 면적 4배는 프레임당 에너지 증가다 |
| `481ad3a` #389 | 넓은 스프라이트에 맞춰 메뉴바 캔버스를 최대 36pt 까지 넓힘 | 포크는 일부러 고정 폭을 쓴다(`PokeDexBarApp.swift:357` "폭이 흔들리면 메뉴바가 떨린다"). 대안(업스트림에 없음): `SpriteTrim` 합집합 경계로 메뉴 프레임을 다듬고 폭은 고정한다 |
| `37763d3` #250 | 저전력 모드에서도 메뉴바 GIF 유지(Power saver 캡) | 포크는 저전력 모드에서 bob 으로 바꾸는 선택을 하고 있다(`:260`). 포크 하한이 이미 0.4s(업스트림 Power saver 캡과 같다)라서 포팅은 "가드 삭제"로 줄어든다. 세션 중 전환 감지 결함은 배치 E 에서 따로 고친다 |

### ④-3 세이브 자동 백업 (2) → Q5

`13e3bf2` #330(로컬 자동 스냅숏 10개·손상 복구·복원 UI, +776줄) · `fd12f00` #446(백업 기록 기본 접기, 같은 커밋이
`ci.yml` 에 스냅숏 아티팩트 업로드 추가). 업스트림 구현은 `CompanionStore`·SaveTransfer 에 묶여 있다.

## ② 해당 없음 (87) — 사유별

### 업스트림 게임 계층 (44) — 포크 게임 계층(Player/: 박사·알·도감·폼·레벨)과 갈라진 코드

모두 업스트림 전용 파일(`CompanionStore`·`CompanionView`·`ShopView`·`BagView`·`SaveTransfer`·`PokemonForm`·
`UnownForm`·`PokemonProfile`·`DifficultySettingsSection`·`PokemonNameLabel`·`Badge`)만 고친다. 공유 파일
(`PopoverView`·`SettingsView`·`FloatingPetPanel`·`PokeTokenBarApp`)을 건드려도 그 헝크는 게임 기능의
진입점뿐이다(`--stat` 전수 확인). 포크에 같은 기능이 필요하면 포크 모양으로 따로 설계할 일이다.

`fd0be71` #142 상점 Uncommon/Rare 알 · `87176e7` #147 컬렉션 탭 분할 · `61c7c99` #156 도감 셀 이름 ·
`d16c3ea` #158 대표 포켓몬 고정 · `79ba760` #211 Raising 배지 · `60808c5` #242 방출해도 도감 유지 ·
`56a3547` #261 알 단계 상점 카드 · `184c5f4` #282 대형 포획 기록 UI 정지 · `b0c6074` #244 난이도 배율(+펫
푸터 토글 — 아래 #284 와 함께 포크가 포팅한 #302 로 대체됨, 토글은 `PopoverView.swift:1118-1126`) · `dec297a` #254
반복 부화 2배 성장 · `b6bf676` #264 개체값·도감 상세 · `087fd0f` #285 도감 스프라이트 애니 · `5963293` #287
난이도 저장 · `1a8a725` #295 상세 이름 영어 깜빡임 · `2ecf7d2` #246 부화 지연 안내 · `2e8efdd` #328 이상한사탕
일괄 · `10d1a07` #288 안농 폼 · `c951492` #291 방출 시 유지 안내 · `4bfae97` #345 외형 선택 · `b4ff5de` #335
전설 알 폐기 방지 · `f0ef5ff` #343 도감 번호 색 · `fe51577` #351 이로치 확률 표기 · `014fcb2` #352 첫 알 힌트 ·
`ae7bd9d` #329 도감 검색·정렬 · `279e112` #370 4x4 그리드 · `9c9c805` #424 진화 체인 중복 · `fad8f1a` #422
껍질몬 HP · `e2f8bcc`·`1a71018` #420 메타몽 이로치 스냅숏(같은 변경의 커밋 2개) · `e772e1f` #398 난이도
슬라이더 라벨 · `26efe4e` #394 스프라이트 클릭→도감 · `e2d01af` #393 도감 휠 페이징 · `46d5d91` #391 타입 배지 ·
`fc66c1e` #390 이로치 필터 버튼 · `eb6ea0c` #378 메타몽 반복 보너스 · `5214b04` #374 도감 이로치 스프라이트 ·
`14e9a6c` #371 상점 다중 구매 · `8771013` #366 빈 가방 상점 바로가기 · `abe0b9a` #392 성장 바 호버 · `656d603`
#380 페이저 히트 영역 · `c328d5c` #429 개체 선택기 · `a4d17d5` #435 뒤로가기 위치 복원 · `04b12da` #376 1~5세대
폼 · `17cf2bf` 폼 캡션 렌더 테스트

### 비-Claude 프로바이더 한도 (15) — 로드맵 제외 결정 유지

- Antigravity 한도: `de6c996` #210 · `66ce498` #221 · `ce65fde` #245 · `aaef5db` #274 · `641e3e8` #323 ·
  `87c6792` #325 · `11197c8` #416 · `2745fde` #414 · `423dd9c` #219 · `1458f5b` #220(그 한도 문자열의 불어 값)
- Cursor 대시보드 API·한도: `4fe965e` #197 · `777ee27` #273 · `f2d5c3e` #426 · `7a5742f` #408 · `5ee12ee` #412
  (대시보드 로그인 만료 안내. 포크 Cursor 는 로컬 로그 리더라 그 안내 자체가 없다)

### 추가 UI 언어 (6) — ko/en/ja 만 유지

`d0c07c6` #159 es · `136e062` #185 fr · `1ecf87f` #215 pt · `77e159c` #234 de · `9be4ea9` #372 ru · `b886b7a` #406 pt 문구

### 한도-창 사탕 지급 (2) — 전제 메커니즘이 포크에 없음 (SP3 판단 유지)

`e94da86` #334 리셋 시 재무장 · `d888793` #375 휘발성 리셋 시각으로 인한 반복 지급. 포크 사탕은 리본 파트너의
토큰 사용에서 나온다. #375 의 교훈("휘발성 필드를 dedup 키에 쓰지 마라")은 포크 CLAUDE.md 에 이미 있다.

### 릴리스 범프·업스트림 문서·스크린샷 (16)

- 버전 범프: `0d2e36b` 2.5.1 · `4c29ca0` 2.5.2 · `77bc9b8` 2.5.3 · `09fd600` 2.5.4 · `42df4e6` 2.5.5 · `77f789d` 2.5.6
- README·스크린샷·투어: `a69444c` #239 · `d186616` #223 · `d4d07c1` · `065b2e1` #297 · `b63fce2` · `594be29` ·
  `2c0212b` · `4617c8a`
- 업스트림 defect-log 전용: `28560eb` #192(전체 파일 읽기 부류·가드 도달성. 포크 CLAUDE.md "한 번도 발동한 적
  없는 가드는 죽어 있다"에 이미 있다) · `7e43566` #204(Antigravity)

### 기타 (4) — 포크에 대상이 없거나 포크의 의도적 선택

- `d4d34e7` #284 펫 토글을 푸터에서 제거: 포크가 포팅한 #302 가 토글을 다시 넣었다. 둘이 상쇄된다
- `8a20c3a` #247 Claude refreshToken 갱신 금지 기록: 포크 소스의 `refreshToken` 사용은 0건이다. 원하면 CLAUDE.md 에 한 줄
- `21c483c` #165 현지화 가드가 모든 `AppLanguage` 를 순회: 포크 테스트의 리터럴 목록(ko/en/ja)이 지금은
  `allCases` 와 같다. 4번째 언어를 더할 때 다시 본다
- `3b2e4c0` #427 PR 에 UI 이미지 필수화: 포크 `.github/PULL_REQUEST_TEMPLATE.md:17-22` 는 일부러 선택 사항으로 둔다

(합계: 게임 44 · 한도 15 · 언어 6 · 사탕 2 · 릴리스·문서 16 · 기타 4 = 87.)

## 업스트림 열린 이슈 3건 — 포크 해당 여부

### #337 — 큰 히스토리에서 Claude 로그 스캔이 CPU 를 계속 점유 → **해당 (전부)**

업스트림: 열림. 수정 PR #338(+200/−22, `LocalUsageCache`·`LocalUsageReader`·`Models`)은 9-21 이후 리뷰 0건이고
충돌(dirty) 상태로 미머지다.

- `Core/LocalUsageCache.swift:11`: `Blob` 에는 mtime·size·entries 만 있고 **바이트 오프셋이 없다.**
- `Core/LocalUsageCache.swift:227-234`: mtime 이나 size 가 바뀌면 `parse(url)` 이 **파일 전체**를 다시 읽는다 →
  자라는 활성 JSONL 을 매번 0바이트부터 파싱한다.
- `Core/LocalUsageReader.swift:346,349`: `String(contentsOf:)` 로 파일 전체를 UTF-8 검증한 뒤 줄로 나눈다(수백 MB).
- `Core/Models.swift:465-467`: `ISO8601Parser` 가 **호출마다 `ISO8601DateFormatter` 를 새로 만든다**(주석은 "파싱
  빈도 낮음"이라고 가정한다). 그런데 assistant 줄마다 호출된다(`LocalUsageReader.swift:398`).
- `Core/LocalUsageCache.swift:152,371-373`: 모든 루트 스캔이 끝난 뒤에만 저장한다 → 끝나지 못한 콜드 스캔은 저장되지
  않아서 재실행할 때마다 콜드 스캔이 반복된다.
- 상한은 mtime 창뿐이다(`LocalUsageReader.swift:1533-1536`, 약 31~37일). 파일 개수·크기 상한은 없다.
- 한 번의 refresh 가 같은 경로를 최대 3번 지난다(`LocalUsageProvider.swift:10`·`:16-17`, `UsageStore.swift:940→1233→1255`).
  기본 주기는 120초(`UsageStore.swift:591`).
- 작업은 메인 액터 밖(`LocalUsageCache` actor)에서 돈다 → UI 정지가 아니라 **CPU·배터리 비용**이다. 2.6GB 히스토리라면
  정상 상태에서도 100~274MB 활성 파일을 2분마다 최대 3번 다시 읽는다.
- **제안**: 배치 B 에서 포크 모양으로 구현한다(Q4). PR #338 은 참고만 한다.

### #443 — OpenCode(OpenChamber) 경유 Claude Code 사용량 이중집계 → **부분 해당 (설정에 따라)**

업스트림: 열림. PR #444(+39/−2)가 열려 있고 메인테이너가 P2 두 건으로 변경을 요청했다.

- 메커니즘: OpenChamber 의 `claude-code` 프로바이더가 Claude Agent SDK 를 부른다 → Claude Code 가
  `~/.claude/projects` 에 JSONL 을 남기고, OpenCode 도 같은 턴을 `providerID="claude-code"` 로 저장한다.
  `providerID="anthropic"`(OpenCode 가 API 를 직접 호출)은 정상적인 OpenCode 사용량이므로 걸러서는 안 된다.
- `Core/LocalAdditionalUsageProvider.swift:196`: `providerID` 가 nil 만 아니면 받는다(`claude-code` 건너뛰기 없음).
- `:199` vs `LocalUsageReader.swift:400`: id 형식이 `opencode|<id>` 와 `msgid|requestId` 로 달라서 교차 dedup 이 불가능하다.
  `UsageStore.swift:229,400,402` 의 프로바이더 합산에도 교차 dedup 은 없다.
- **포크가 레거시 `message` 테이블만 읽으므로**(`:232,238`, #363 미포팅): OpenCode 가 v1 테이블을 쓰면 이중집계된다.
  v2 를 쓰면 미러 행을 아예 읽지 않아 이중집계는 없지만, 대신 v2 의 정상 사용량도 0이다(별도 공백 → #363).
- **제안**: 배치 C 에서 #143 → #363 → 미러 건너뛰기 순서로 한다(방식은 Q3). 포크 원장은 일 고점 하나라서
  (`Player/PlayerStore.swift:122-124`) 업그레이드 당일 미러 행을 빼면 성장이 멈춘다 → #143 이 먼저여야 하는 이유다.

### #439 — Claude 데스크톱 Projects 사용량 미집계 → **해당 (데이터 소스의 한계, 코드 결함 아님)**

업스트림: 열림, PR·커밋 없음.

- `Core/LocalUsageReader.swift:124-130`: 루트는 `CLAUDE_CONFIG_DIR`·`~/.config/claude/projects`·`~/.claude/projects`, 그리고
  데스크톱의 `local-agent-mode-sessions`·`claude-code-sessions` 다. 즉 Code 탭 사용량뿐이다.
- 이슈 보고에 따르면 Projects 는 서버에서 돌고 로컬에는 claude.ai 웹뷰 저장소(IndexedDB·Local Storage)만 남는다.
  사용량 로그가 아니다. `SessionKeyLimitsProvider.swift:11,165` 의 세션 키 경로도 5h·주간 한도만 읽는다.
- `README.md:388` 근처에도 "claude.ai 채팅·Projects 제외" 안내가 없다.
- **제안**: 배치 H 에서 README 안내만 넣는다. "한도 % 상승분으로 동반자를 키우자" 같은 확장은 게임 밸런스를 바꾸므로 범위 밖이다.

## SP3 이연 결함과의 관계

`docs/ops/sp3-deferred-minors.md`(로컬 노트) 대조:

- **이연 #2(highest 모드가 만료 계정 동결값을 따라감)·#5(Keychain 열거 단계 취소 후 두 번째 다이얼로그)**: 업스트림에도
  있는 결함이다. 업스트림 main 에서 `OAuthLimitsProvider`·`ClaudeAccountUsage`·`SessionKeyLimitsProvider`·`ClaudeAccountRoots`
  를 마지막으로 고친 커밋은 #355(9-25)이고 **그 뒤 수정은 없다** → 업스트림이 고친 적 없으니 포크가 직접 고쳐야 하고, 역기여
  후보로 남는다. SP4 포팅으로는 해소되지 않는다.
- **이연 #7(`sessionKeyError` 저장형 현지화 문자열)**: 업스트림 #290 의 오류 문구 부분과 같은 결함이다 → 배치 F 에서 같이 고친다.
- **이연 #8(업스트림 잔존 주석)**: #256(ccusage 주석)과 같은 손질이다 → 배치 H 에서 한 커밋으로 묶는다.
- 나머지(#1·#3·#4·#6)는 업스트림 커밋과 무관하다. 포크 결함 대응 레인의 몫이다.

## 포팅 방식 (SP1~SP3 과 동일 + SP4 특칙)

- 커밋 단위: `git show <hash> | sed 's|PokeTokenBar|PokeDexBar|g' | git apply --reject`. 리젝트는 파일별로 수동 이식하고
  **일괄 삭제는 금지**한다. 업스트림 커밋의 전체 diff 를 먼저 읽는다. 테스트를 먼저 이식해 RED 를 확인한 뒤 소스를 넣는다(GREEN).
  커밋 메시지는 영어로, `(upstream #NNN)` 을 붙인다. 업스트림 커밋이 없는 항목(이슈 수정·포크 결함)은 `(upstream issue #NNN)` 또는
  참조 없이 쓴다.
- **부분 포팅 6건**(`a6ed409`·`a910767`·`dc6de41`·`d6fb966`·`2fab082`·`5e08e6f`)은 기계 적용 대신 해당 헝크만 수동으로
  이식한다. 버리는 헝크는 커밋 본문에 적는다.
- **외부 포맷 writer 검증 선행**: #318(`cost-state`), #363(`session_message` 스키마), #337(JSONL 증분 경계)은 CLAUDE.md
  "외부 로그 포맷은 상위 소스의 writer 로 검증" 규칙에 따라 writer 나 실파일로 계약을 먼저 확정한다. 픽스처는 실응답에서 잘라 온다.
- **미머지 업스트림 PR(#338·#444)은 참고 자료일 뿐이다.** 리뷰를 통과하지 않은 코드라서 포크 테스트로 처음부터 검증한다.
- 포크 규칙이 우선한다: 메뉴바 idle 규율(트랜잭션·diff-gate·0.4s 하한·tolerance 0.5), 펫 `frameFloor = 0`, 자동 폴의
  Keychain 무접촉, 테스트의 실 저장소 무접촉. 업스트림 헝크가 이것들을 약화시키면 그 헝크는 버린다.
- CompanionStore → PlayerStore, 7언어 → ko/en/ja 트림, Antigravity·Cursor API·SaveTransfer 헝크 버림 — SP2·SP3 관례 그대로.
- `git add -A` 금지 범위(미추적 로컬 파일)와 `*.rej` 청소는 SP2 규칙 그대로.

## 검증

- 배치마다 전체 `swift test`(배치 A 이후로는 실 `usage-cache.json` 의 mtime 이 스위트 실행 전후로 변하지 않음을 한 번 확인).
- 배치 B: 같은 로컬 로그에 대한 오늘/주/월 합계를 #337 적용 전후로 비교한다(증분 파싱은 **합계를 바꾸면 안 된다** — 바뀌면 결함).
  덧붙임·잘림·반쯤 쓰인 줄 테스트를 넣고, Dev 빌드에서 idle CPU 를 실측한다.
- 배치 C: #143 트리거 브랜치를 단독으로 테스트한다(한 프로바이더만 하락하고 다른 프로바이더는 증가할 때 적립이 계속되는지).
  #443 은 `providerID=="anthropic"` 대조군으로 정상 OpenCode 사용량이 남는지 확인한다.
- 배치 D: e2e 에 "인스턴스 1개" 단언을 넣는다. Dev 빌드에서 "로그인 시 실행" 토글 후 메뉴바 아이콘이 1개인지 확인한다.
- 배치 E: 메뉴바 변경은 **설치된 primary 앱 교체로만** 실측한다(CLAUDE.md). #255 전후의 idle CPU·wakeup 을 비교한다.
- 배치 G: 산출 바이너리를 `lipo -archs` 로 확인한다(arm64 x86_64). 가능하면 Rosetta/Intel 실행을 1회 확인한다.
- UI 변경 배치(D·E·F)는 릴리스 때 스크린샷을 다시 만든다. `feat:` 이면서 `Sources/**/UI/` 를 바꾸는 커밋이 생기면(Q2 의 #373)
  신규 에셋 하드 게이트에 걸린다는 점을 릴리스 레인에 넘긴다.

## 확인 못 한 것

- **실데이터 검증 없음**: #318 `cost-state` 레코드, #363 OpenCode v2 스키마, #443 미러 행을 사용자 로컬 파일로 확인하지 않았다
  (읽기 전용 트리아지 범위). 포팅 착수 때 writer·실파일로 확정한다.
- **Sonnet 5.5 캐시 읽기 가격**(dc6de41): 업스트림($0.10, 10-16 확인)과 포크($0.20, 09-29 확인)가 다르다. 1차 가격 페이지를 보지 않았다.
- **#337 실측 수치**는 이슈 보고자의 수치다(2.6GB 히스토리). 이 기기의 `~/.claude/projects` 크기와 idle CPU 는 재지 않았다.
- **#212 capFrameRate 의 체감**(부드러운 슬로모션 → 끊기지만 제 속도)은 실물을 보지 않았다. 배치 E 에서 사용자 확인이 필요하다.
- **#400 Intel 실행**: 지금 배포본이 Intel 에서 실패한다는 것은 빌드 스크립트로 추론한 결론이다. Intel 실기기로 확인하지 않았다.
- 브리프 이후 업스트림이 더 움직이면(이 문서는 `77f789d` 기준) 포팅 착수 때 `git log 77f789d..upstream/main` 만 추가로 트리아지한다.
