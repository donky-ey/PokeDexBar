import XCTest
@testable import PokeDexBar

/// 비번들 실행(`swift test`·로우 바이너리)은 실 앱의 `Application Support` 를 읽지도 쓰지도 않는다.
///
/// `AppEnv.storageName` 은 비번들에서 설치본과 같은 "PokeDexBar" 라, 저장소마다 기본 경로를 따로
/// 조립하던 시절에는 테스트가 실 `usage-cache.json` 을 다시 쓰고(업스트림 #359), 실 스프라이트 캐시에
/// 가짜 GIF 를 넣고, 세션 키 픽스처를 실 폴더에 남겼다. 경로를 주입하는 테스트는 그 테스트만 지킨다 —
/// 기본 경로를 타는 코드(`.shared`·기본 프로바이더)는 주입이 안 닿는다. 그래서 막는 자리는 저장소가
/// 아니라 뿌리(`AppEnv.supportDirectory`)이고, 이 파일은 그 뿌리와 "모두가 뿌리를 거친다"를 잠근다.
final class AppStorageIsolationTests: XCTestCase {
    private func isUnderUserLocation(_ url: URL) -> Bool {
        let user = AppEnv.userSupportDirectory.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        return path == user || path.hasPrefix(user + "/")
    }

    /// 트리거 브랜치 — 비번들 실행 + 기본 경로. xctest 는 번들이 아니므로 인자 없는 호출이 곧 그 경로다.
    func testANonBundledRunGetsAnIsolatedSupportDirectory() {
        XCTAssertFalse(isUnderUserLocation(AppEnv.supportDirectoryURL(isBundledApp: false)))
        XCTAssertFalse(isUnderUserLocation(AppEnv.supportDirectoryURL()),
                       "swift test 가 실 Application Support 를 기본 저장소로 쓴다")
        // 대조군 — 번들 앱(정식·Dev)은 예전 자리를 그대로 써야 세이브가 이어진다.
        XCTAssertEqual(AppEnv.supportDirectoryURL(isBundledApp: true).standardizedFileURL,
                       AppEnv.userSupportDirectory.standardizedFileURL)
    }

    /// 저장소마다 기본 경로가 뿌리를 거치는지. 하나라도 따로 조립하면 그 저장소만 실 폴더로 샌다.
    @MainActor
    func testEveryDefaultStorePathStaysOutsideTheUserLocation() {
        let defaults: [(String, URL)] = [
            ("usage-cache.json", LocalUsageCache().fileURL),
            ("player-state.json", PlayerStore.defaultURL()),
            ("sprites", SpriteLoader.cacheDir),
            ("weather.json", WeatherClient.defaultFileURL()),
            ("base-index.json", PokeAPIClient.baseIndexFile),
            ("session-key.json", SessionKeyStore().fileURL),
        ]
        for (name, url) in defaults {
            XCTAssertFalse(isUnderUserLocation(url), "\(name) 의 기본 경로가 실 앱 폴더다: \(url.path)")
        }
    }

    /// 앞으로 생길 저장소까지 — `Application Support` 경로는 `AppEnv` 한 곳에서만 조립한다.
    func testNoAppSupportPathIsComposedOutsideAppEnv() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/PokeDexBar")
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        var offenders: [String] = []
        for case let url as URL in enumerator
        where url.pathExtension == "swift" && url.lastPathComponent != "AppEnv.swift" {
            let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false)
            for (index, line) in lines.enumerated() {
                // 주석을 먼저 걷어낸다 — 통짜 검색은 주석의 같은 낱말에 걸려, 코드를 지워도 통과한다.
                let code = line.range(of: "//").map { String(line[..<$0.lowerBound]) } ?? String(line)
                if code.contains("applicationSupportDirectory") {
                    offenders.append("\(url.lastPathComponent):\(index + 1)")
                }
            }
        }
        XCTAssertTrue(offenders.isEmpty,
                      "Application Support 경로는 AppEnv.supportDirectory() 로만 얻는다: \(offenders.joined(separator: ", "))")
    }
}
