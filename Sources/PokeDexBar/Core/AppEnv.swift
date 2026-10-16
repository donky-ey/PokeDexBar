import Foundation

/// 실행 환경 판별 — 한 곳에서만 정의해 중복 게이트의 drift(일부만 조건이 어긋나는 것)를 막는다.
enum AppEnv {
    /// 정식 `.app` 번들로 실행 중인가. 알림 전송·키체인 읽기·스프라이트 프리패치·프로덕션 로그 기록 등
    /// "실앱 전용" 부수효과의 단일 게이트 — `swift test`/로우 바이너리(dev 실행)에선 false.
    /// bundleIdentifier(Info.plist)와 경로 접미사를 함께 확인(둘 다 실앱에서만 참).
    static var isBundledApp: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundlePath.hasSuffix(".app")
    }

    /// `PTB_PARITY=1` — 라이브 엔드포인트를 허용하는 QA/패리티 실행(패리티 스모크가 이미 쓰는
    /// 플래그). `isBundledApp` 이 닫아 둔 게이트를 여는 용도로만 쓰인다.
    static var isParityRun: Bool {
        ProcessInfo.processInfo.environment["PTB_PARITY"] == "1"
    }

    /// 테스트가 프로바이더의 실 네트워크 코드를 **스텁 전송**(URLProtocol·주입 URLSession)에 대고
    /// 돌릴 때 연다. 테스트 안에서 켜고 `defer` 로 끈다.
    nonisolated(unsafe) static var allowLiveFetchForTesting = false

    /// 한도 프로바이더가 사용자 자격증명을 라이브 엔드포인트로 보낼 수 있는가. `swift test` 와
    /// 로우 `swift build` 바이너리에선 닫힌다 — 스텁을 주입하지 않은 테스트가 아니면
    /// `~/.claude/.credentials.json` 의 실 로그인으로 Anthropic 을 때려 rate limit 을 소모한다.
    /// 게이트는 자격증명 읽기 **뒤**·네트워크 **앞** — Keychain 경로 테스트가 실 읽기를 계속
    /// 관찰해야 하기 때문. `LiveCredentialCallGateTests` 가 전 프로바이더에 이를 강제한다. (#355)
    static var allowsLiveLimitsFetch: Bool {
        isBundledApp || isParityRun || allowLiveFetchForTesting
    }

    #if DEBUG
    /// 테스트 전용 버전 덮어쓰기. `swift test` 의 `Bundle.main` 은 xctest 러너라 앱과 무관한 값을
    /// 돌려준다 — 설정 화면을 그대로 찍는 스크린샷 생성기가 릴리스 버전을 넣을 수 있게 하는 seam.
    /// 릴리스 빌드에는 존재하지 않는다.
    nonisolated(unsafe) static var appVersionOverride: String?
    #endif

    /// 저장 공간 이름 — Application Support 디렉터리와 로그 파일 이름의 단일 소스.
    ///
    /// 개발 빌드(`PokeDexBar Dev`)를 정식 설치본과 **나란히 깔고 쓰기 위해서** 있다. 둘이 같은
    /// 이름을 쓰면 세이브·사용량 캐시·로그를 서로 덮어써서, 한쪽에서 시험 삼아 한 일이 다른 쪽
    /// 진행에 그대로 섞인다. `CFBundleName` 에서 뽑으므로 정식 빌드는 예전과 같은 "PokeDexBar" 를
    /// 그대로 쓰고(기존 세이브 경로 유지), 개발 빌드만 "PokeDexBarDev" 로 갈라진다.
    static var storageName: String {
        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
        guard isBundledApp, let name else { return "PokeDexBar" }
        return name.replacingOccurrences(of: " ", with: "")
    }

    /// 사용자 도메인의 표준 디렉터리. **`[0]` 을 안 쓴다** — `FileManager.urls(for:in:)` 는
    /// 배열을 돌려주고 빈 배열이면 첨자가 프로세스를 죽인다. 실제로 비는 일은 드물지만,
    /// 크래시 진단을 넣는 마당에 죽을 수 있는 자리를 남겨 둘 이유가 없다.
    /// 홈 디렉터리 기준으로 떨어뜨리면 최소한 앱이 살아서 동작한다.
    static func userDirectory(_ directory: FileManager.SearchPathDirectory) -> URL {
        if let url = FileManager.default.urls(for: directory, in: .userDomainMask).first {
            return url
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        return switch directory {
        case .applicationSupportDirectory: home.appendingPathComponent("Library/Application Support")
        case .libraryDirectory: home.appendingPathComponent("Library")
        case .cachesDirectory: home.appendingPathComponent("Library/Caches")
        default: home
        }
    }

    /// 실 사용자 위치(`~/Library/Application Support/<storageName>`). 번들 앱만 여기를 쓴다.
    /// 만들지 않는다 — 테스트가 "여기를 안 건드린다"를 단언할 때의 기준점이기도 하다.
    static var userSupportDirectory: URL {
        userDirectory(.applicationSupportDirectory).appendingPathComponent(storageName, isDirectory: true)
    }

    /// 비번들 실행의 저장소 — 실행마다 새 임시 폴더라 실행끼리도 섞이지 않는다. 이름은 UUID 다: PID 는
    /// 재사용되므로 PID 이름이면 뒤 실행이 앞 실행이 남긴 캐시를 그대로 물려받는다(리뷰에서 실측).
    private static let isolatedSupportDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("PokeDexBar-\(UUID().uuidString)", isDirectory: true)

    /// 이 실행이 쓸 Application Support 경로(만들지 않는다).
    ///
    /// **비번들 실행(`swift test`·로우 바이너리)은 실 폴더를 쓰지 않는다.** `storageName` 이 비번들에서
    /// 설치본과 같은 "PokeDexBar" 라, 여기서 가르지 않으면 테스트가 실 세이브·사용량 캐시·스프라이트
    /// 캐시를 읽고 쓴다(업스트림 #359 는 usage-cache.json 이 테스트 한 번에 다시 써지는 것을 실측했다).
    /// 경로 주입은 주입한 테스트만 지킨다 — `.shared` 나 기본 프로바이더처럼 기본 경로를 타는 코드는
    /// 이 뿌리에서만 막힌다. App Support 경로는 반드시 이 함수(또는 `supportDirectory`)로 얻는다
    /// (`AppStorageIsolationTests` 가 소스를 훑어 강제한다).
    static func supportDirectoryURL(isBundledApp: Bool = AppEnv.isBundledApp) -> URL {
        isBundledApp ? userSupportDirectory : isolatedSupportDirectory
    }

    /// 이 실행의 Application Support 디렉터리. 없으면 만든다.
    static func supportDirectory(isBundledApp: Bool = AppEnv.isBundledApp) -> URL {
        let dir = supportDirectoryURL(isBundledApp: isBundledApp)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 개발 빌드인가 — 메뉴바에 표식을 붙여 정식 설치본과 눈으로 구분하기 위해서만 쓴다.
    static var isDevBuild: Bool { storageName != "PokeDexBar" }

    /// 표시·전송용 앱 버전(`CFBundleShortVersionString`). 이 키를 읽는 곳이 여럿이라 여기 하나로 모은다.
    /// 번들이 아닌 실행(테스트·로우 바이너리)에서는 의미 있는 값이 없으므로 호출부가 폴백을 정한다.
    static var appVersion: String? {
        #if DEBUG
        if let appVersionOverride { return appVersionOverride }
        #endif
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }
}
