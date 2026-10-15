# SP3 — 업스트림 Claude 계정·한도 포팅 (설계)

2026-10-15 · 포팅 로드맵(SP1→SP2→SP3)의 마지막 하위 프로젝트. SP1(조사·폴링)·SP2(표시 24커밋)는
main 머지 완료. SP3 은 **Claude 계정·한도 계층**: 계정 식별, 세션 키 경로(키체인 무접촉 한도 갱신),
다중 계정 추적, 그리고 테스트의 실 엔드포인트 호출 차단. 사용자 결정(확정): 세션 키 (a) 와
다중 계정 (b) **둘 다** + #344.

## 전제 — 포크와 업스트림의 키체인 정책은 같은 결론에 도달해 있다

포크는 #58 이후 자체 규율(CLAUDE.md: 자동 폴링 키체인 금지, `fetch(allowKeychainPrompt:)` 게이트,
`testAutoRefreshUsesNoPromptPathManualUsesPromptPath`)을 갖고 있고, 업스트림도 #280/#327 에서
"automatic polls never read the Keychain" 으로 **같은 정책**을 명문화했다. 충돌이 아니라 수렴이다 —
포팅 시 포크 게이트는 유지하고 업스트림 구조를 그 위에 얹는다. 단 포크 `OAuthLimitsProvider` 는
271줄(분기점 229줄 + 포크 게이트 42줄), 업스트림은 574줄이라 **이 파일은 전 배치에서 수동 포팅이
기본**이다(mechanical apply 는 시도하되 리젝트 전제).

## 포팅 항목 — 의존 순서의 배치 6개 (총 11커밋 + 이월 1건)

업스트림 시간순이 곧 의존 순서다(SP2 룰링 계승: 시간순 실행).

### 배치 A — 계정 식별·키체인 정리 (4커밋)

| 업스트림 | 내용 | 판정 |
|---|---|---|
| `40f4108` #199 | 공식 한도에 **소유 계정 라벨**(oauth profile 엔드포인트로 email·org 조회, 토큰별 캐시) | 적용 — 두 계정이 같은 Keychain 항목을 덮어쓸 때 "누구의 5h/주간인가"를 표시. 프로필 호출 실패 시 기존 표시 그대로(best effort) |
| `3214f83` #227/#228 | **제자리 계정 전환을 자동 폴이 감지** — 캐시 히트 전에 `credentials.json` 을 피크(키체인은 여전히 자동 경로 밖) | 적용 — Antigravity 토큰 캐시 헝크는 버림(포크 미보유) |
| `e81e620` #232 | 여러 Keychain 항목에 걸친 OAuth 해석 | 적용 — 수동 갱신 경로에만 적용됨을 확인(포크 게이트 뒤) |
| `c9c016d` #280 | **MCP 더미 항목보다 사용자 계정 우선**(NSUserName > email > general > unknown), 취소/실패 시 즉시 중단(프롬프트 폭탄 방지), 부재 시 불필요 쿼리 생략 | 적용 — 수동 갱신 1회 프롬프트의 품질 개선. 포크 회귀 테스트(`testAutoRefresh…`)는 그대로 통과해야 한다 |

### 배치 B — 세션 키 경로 (2커밋) = (a)

| 업스트림 | 내용 | 판정 |
|---|---|---|
| `8953ea8` #241 | **claude.ai sessionKey 쿠키로 공식 한도 조회**(`SessionKeyLimitsProvider` 신설 314줄, 설정 Advanced 에 입력, `ChainedLimitsProvider` 로 OAuth 폴백). 응답 스키마가 oauth/usage 와 동일해 `LimitStatus` 재사용. 키체인 무접촉 → **자동 폴링이 프롬프트 없이 한도를 계속 갱신** | 적용 — 포크의 미해결 문제(캐시 만료 후 수동 갱신 의존, CLAUDE.md "완전 근절은 notarization 뿐")에 대한 업스트림의 실제 해법. org 선택 로직·429 Retry-After 백오프 포함. 검증 함정: curl 은 Cloudflare 챌린지로 403 — `scripts/probe-session-key.swift` 도 같이 가져온다 |
| `7898065` #275 | 키체인 한계 안내 **앰비언트 도움 팝오버** + 설정의 세션 키 입력으로 바로 이동(자동 스크롤·포커스) | 적용 — Localization 은 ko/en/ja 로 트림 |

### 배치 C — 수동 갱신·전환 반영 (1커밋)

| 업스트림 | 내용 | 판정 |
|---|---|---|
| `3272509` #302 | **수동 갱신은 아직 유효한 캐시도 건너뛰고** 재읽기(제자리 계정 전환이 401 전엔 안 보이던 문제) + 팝오버 푸터에서 플로팅 펫 다시 켜기 | 적용 — 펫 토글 반쪽은 포크 `FloatingPetPanel`/설정과 대조해 수동(포크에 이미 있으면 스킵) |

### 배치 D — 다중 계정 (3커밋) = (b)

| 업스트림 | 내용 | 판정 |
|---|---|---|
| `e5b4800` #327 | **여러 Claude 계정 추적**(+3,419줄): `~/.claude-*`/`~/.claude_*`/`CLAUDE_CONFIG_DIR` 자동 감지 + 설정 수동 등록(`ClaudeAccountRoots` 신설), 계정별 공식 한도 탭(`ClaudeAccountUsage` 신설), 폴더별 토큰 캐시(.credentials.json 또는 `…-<sha256>` Keychain 항목 — 자동 폴은 역시 키체인 무접촉), 계정별 만료/429 격리, 기본 계정은 기존 키 유지(세이브 호환) | 적용 — **가장 큰 덩어리.** CompanionStore 알림/사탕 헝크는 포크 구조로 치환(아래 제외 참조), FloatingPetPanel·메뉴바는 "기본 계정 따름" 유지. 포크 `LocalUsageReader` 의 기존 CLAUDE_CONFIG_DIR 다중 루트 스캔과 계정 귀속을 접합 |
| `e76a8e0` #344 | **포크된 세션의 사용량을 원본 계정에 귀속**(dedup 턴이 발견된 모든 세션 id 보존, 턴 시각 이전 프롬프트가 있는 원본 세션 우선) | 적용 — 사용자 명시 요청. SP1 의 #129(포크 세션 재생 제외)와 같은 부류 — 그 dedup 구조 위에 귀속 축만 더한다 |
| `eed5b73` #346 | **계정별 세션 키**(추가 계정도 키체인 없이 자동 갱신) | 적용 — #241+#327 결합부 |

### 배치 E — 테스트 안전 게이트 (1커밋)

| 업스트림 | 내용 | 판정 |
|---|---|---|
| `671c1ec` #355 | **`swift test` 가 실 사용자 자격증명으로 라이브 한도 엔드포인트를 때리지 않게** 네트워크 경계에 `AppEnv.allowsLiveLimitsFetch` 게이트(.app 번들 or PTB_PARITY=1 or 테스트 명시 옵트인). 게이트는 자격증명 읽기 뒤·네트워크 앞이라 KeychainAutoPathTests 류는 계속 실 읽기를 관찰 | 적용 — 포크도 같은 위험(UsageStore 가 기본값으로 실 프로바이더 주입). Cursor/Antigravity 경계 헝크는 버림. **배치 A 보다 먼저 당겨도 된다** — 실행 시 시간순 예외로 최우선 적용을 권장(이후 배치의 테스트가 전부 이 게이트의 보호를 받는다) |

### 배치 F — SP2 이월 (업스트림 커밋 없음, 1건)

- **메뉴바 한도 소스의 다중 계정화**: SP2 #357 포팅 때 업스트림의 `menuClaudeAccount`(다중 계정
  소스)를 `limits?.fiveHour` 로 치환해 두었다(SP2 룰링: SP3 대상). #327 이 들어온 뒤 업스트림
  원형대로 복원한다 — 단 포크 컴팩트 게이트(오늘 사용>0)는 유지.

## 제외

- **`e94da86` #334 (한도 창 리셋 시 사탕 재지급 재무장)** — 업스트림의 "한도 창 키로 레어사탕 지급"
  메커니즘(CompanionStore `candyGrantTier`+SaveTransfer) 자체가 포크에 없다. 포크의 사탕은 리본
  파트너의 토큰 사용(`candyProgress`/`candyYield`)에서 나온다. 전제 기능이 없으므로 수정도 무의미.
  (CLAUDE.md §상태 파일 분류의 `candyGrantTier` 언급은 업스트림 참조 — 포팅하게 되면 그때 이 판단 재검토.)
- **비-Claude 프로바이더 한도**: Antigravity(#210·#245·#274), Cursor(#273·#408) 및 각 커밋 안의
  해당 헝크 — 로드맵 ④ 제외 결정 그대로.
- `d4d07c1` 등 docs/스크린샷 커밋 — 릴리스 시점 작업(CLAUDE.md 릴리스 절차가 집행).

## 포팅 방식 (SP1·SP2 와 동일 + 특칙)

- 커밋 단위 `git show <hash> | sed s|PokeTokenBar|PokeDexBar|g | git apply --reject`, 리젝트는
  파일별 수동 — **일괄 삭제 금지**(SP1·SP2 에서 두 번 밟은 부류). 테스트 먼저(RED)→소스(GREEN).
- 커밋 메시지 영어 + `(upstream #NNN)`.
- `OAuthLimitsProvider` 는 전 배치 수동 전제(위 전제 절). 포크 게이트(`allowKeychainPrompt`)와
  회귀 테스트는 **불변 조건** — 업스트림 헝크가 이를 약화시키면 포크 규율 우선.
- CompanionStore→PlayerStore, 7언어→ko/en/ja 트림, Antigravity/Cursor/Aside 헝크 버림 — SP2 관례.
- 업스트림 테스트 파일 중 `AdditionalClaudeAccountsTests`(1,925줄)·`SessionKeyLimitsTests`(555줄)·
  `AccountSessionKeyTests`·`CredentialSwitchCacheTests` 는 포크 구조에 맞춰 선별 이식(업스트림 전용
  모델 의존 테스트는 삭제하되 그 의도를 포크 모양으로 재작성).
- 네트워크 실검증: 세션 키 경로는 curl 불가(Cloudflare) — `scripts/probe-session-key.swift` +
  사용자 세션 키로 실측 1회(사용자 개입 필요, 실행 단계에서 요청).

## 검증

- 배치마다 전체 `swift test` 게이트. #355 게이트가 들어온 뒤로는 **스위트가 실 엔드포인트를 안
  때리는지**를 LiveCredentialCallGateTests 류로 상시 보증.
- 다중 계정은 실제 두 번째 계정 없이도: 임시 `~/.claude-test-*` 픽스처 폴더로 감지·귀속·만료 격리를
  테스트(실 세이브·실 자격증명 무접촉).
- Dev 빌드(`PTB_DEV=1 PTB_INSTALL=1`) 실물 확인: 계정 라벨, 세션 키 입력→자동 갱신, 계정 탭.
- 키체인 프롬프트 0 회 확인: 자동 폴 경로에서 `SecItemCopyMatching` 불호출(기존 회귀 테스트 + 수동
  관찰). 마무리는 신선 컨텍스트 전체 리뷰 1회(SP2 와 동일).

## 이후 (이 스펙 밖)

- 릴리스(버전·스크린샷 신규 에셋·README/랜딩) — 자연어 트리거 시 CLAUDE.md 절차.
- SP2 이월 minor 4건(Grok noteUnpriced 마킹, 죽은 코드, 낡은 주석, prevMonthDaily 중복)은 SP3
  실행 중 해당 파일을 지나갈 때 편승 정리 가능(별도 과업 아님).
