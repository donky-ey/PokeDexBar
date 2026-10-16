import XCTest
@testable import PokeDexBar

final class UpdateCheckerTests: XCTestCase {
    func testNewerPatch() {
        XCTAssertTrue(UpdateChecker.isNewer("2.0.2", than: "2.0.1"))
    }
    func testSameIsNotNewer() {
        XCTAssertFalse(UpdateChecker.isNewer("2.0.1", than: "2.0.1"))
    }
    func testOlderIsNotNewer() {
        XCTAssertFalse(UpdateChecker.isNewer("2.0.0", than: "2.0.1"))
        XCTAssertFalse(UpdateChecker.isNewer("2.0.9", than: "2.1.0"))
    }
    func testNumericNotLexical() {
        // "2.0.10" 은 "2.0.9" 보다 높다 (문자열 비교면 반대로 틀림)
        XCTAssertTrue(UpdateChecker.isNewer("2.0.10", than: "2.0.9"))
    }
    func testMinorAndMajor() {
        XCTAssertTrue(UpdateChecker.isNewer("2.1.0", than: "2.0.9"))
        XCTAssertTrue(UpdateChecker.isNewer("3.0.0", than: "2.9.9"))
    }
    func testDifferentComponentCounts() {
        XCTAssertTrue(UpdateChecker.isNewer("2.0.1", than: "2.0"))   // 2.0.1 > 2.0.0
        XCTAssertFalse(UpdateChecker.isNewer("2.0", than: "2.0.0"))  // 동일
    }

    /// brew cask 이름은 이 앱 고유의 것이어야 한다 — 리브랜딩 때 kebab-case 리터럴이 rename 정규식에
    /// 안 걸려 upstream fork 의 cask 를 대신 확인/업그레이드하던 회귀(#task1 리뷰)의 가드.
    /// brewCaskPath()/launchDetachedUpgrade() 둘 다 이 상수 하나만 참조하므로, 이후 이름이 바뀌어도
    /// 두 사용처가 따로 놀 수 없다 — 이 테스트는 그 단일 소스가 여전히 우리 앱을 가리키는지만 고정한다.
    func testCaskNameIsOwnApp() {
        XCTAssertEqual(UpdateChecker.caskName, "poke-dex-bar")
    }

    // MARK: - Detached upgrade script wait loop (upstream #175)

    func testDetachedUpgradeScriptWaitsOnPidNotProcessName() {
        let script = UpdateChecker.detachedUpgradeScript
        XCTAssertFalse(
            script.contains("pgrep -x"),
            "pgrep -x matches any instance by name and always times out when a duplicate runs"
        )
        XCTAssertTrue(
            script.contains("kill -0 \"$3\""),
            "the wait loop must wait on the specific terminating PID via $3"
        )
    }

    func testDetachedUpgradeScriptUsesPositionalParameters() {
        let script = UpdateChecker.detachedUpgradeScript
        XCTAssertTrue(script.contains("\"$1\" update"), "must execute brew via $1 positional arg")
        XCTAssertTrue(script.contains("\"$1\" upgrade"), "must execute brew upgrade via $1 positional arg")
        XCTAssertTrue(script.contains("open \"$2\""), "must open bundlePath via $2 positional arg")
        // 포크: cask 이름은 단일 상수에서 온다(위 testCaskNameIsOwnApp) — 스크립트가 그 상수를 쓰는지까지.
        XCTAssertTrue(script.contains("--cask \(UpdateChecker.caskName)"), "the script must upgrade this app's cask")
    }

    // MARK: - Skipped release (upstream #311)

    /// "이 버전 건너뛰기"는 배너만 숨긴다 — 다음 확인도 그 릴리스가 있다는 걸 알아야 하고,
    /// 설정은 그걸 "최신"으로 다뤄선 안 된다.
    @MainActor
    func testSkippedReleaseStaysVisibleAndANewerOneReturnsToTheBanner() {
        let suite = "UpdateCheckerTests.skip.\(UUID().uuidString)"
        let box = UserDefaults(suiteName: suite)!
        defer { box.removePersistentDomain(forName: suite) }
        let checker = UpdateChecker(currentVersion: "2.5.3", defaults: box)

        checker.consider(latest: "2.5.4", url: "https://github.com/donky-ey/PokeDexBar/releases/tag/v2.5.4")
        XCTAssertEqual(checker.available?.version, "2.5.4")
        XCTAssertNil(checker.skipped)
        XCTAssertEqual(checker.settingsNotice, .offer("2.5.4"))

        checker.skipCurrent()
        XCTAssertNil(checker.available, "the popover banner stays hidden")
        XCTAssertEqual(checker.skipped?.version, "2.5.4")
        XCTAssertEqual(checker.settingsNotice, .skipped("2.5.4"))
        XCTAssertEqual(box.string(forKey: "skippedUpdateVersion"), "2.5.4")

        checker.consider(latest: "v2.5.4", url: "https://github.com/donky-ey/PokeDexBar/releases/tag/v2.5.4")
        XCTAssertNil(checker.available)
        XCTAssertEqual(checker.settingsNotice, .skipped("2.5.4"), "a skipped version is not the latest installed")

        checker.consider(latest: "2.5.5", url: "https://github.com/donky-ey/PokeDexBar/releases/tag/v2.5.5")
        XCTAssertEqual(checker.available?.version, "2.5.5")
        XCTAssertNil(checker.skipped)
        XCTAssertEqual(checker.settingsNotice, .offer("2.5.5"))

        checker.consider(latest: "2.5.3", url: "https://github.com/donky-ey/PokeDexBar/releases/tag/v2.5.3")
        XCTAssertEqual(checker.settingsNotice, .current, "the installed release is the latest")
    }

    @MainActor
    func testShowAgainRestoresTheBannerAndUpdateUsesTheSkippedRelease() {
        let suite = "UpdateCheckerTests.restore.\(UUID().uuidString)"
        let box = UserDefaults(suiteName: suite)!
        defer { box.removePersistentDomain(forName: suite) }
        let checker = UpdateChecker(currentVersion: "2.5.3", defaults: box)
        let url = "https://github.com/donky-ey/PokeDexBar/releases/tag/v2.5.4"
        checker.consider(latest: "2.5.4", url: url)
        checker.skipCurrent()

        XCTAssertEqual(checker.updateTarget?.url, url, "Settings can still install a skipped release")

        checker.showSkippedAgain()
        XCTAssertEqual(checker.available?.version, "2.5.4")
        XCTAssertNil(checker.skipped)
        XCTAssertNil(box.string(forKey: "skippedUpdateVersion"))
        XCTAssertEqual(checker.settingsNotice, .offer("2.5.4"))
    }

    /// 포크: 한국어 문구는 버전 끝자리 받침에 맞춰 조사를 고른다("v1.19.0을" / "v1.19.2를").
    func testSkippedVersionCopyPicksTheParticleAndKeepsTheVersion() {
        XCTAssertEqual(L(.ko).skippedVersion("1.19.0"), "v1.19.0을 건너뛰었어요")
        XCTAssertEqual(L(.ko).skippedVersion("1.19.2"), "v1.19.2를 건너뛰었어요")
        XCTAssertTrue(L(.en).skippedVersion("1.19.2").contains("v1.19.2"))
        XCTAssertTrue(L(.ja).skippedVersion("1.19.2").contains("v1.19.2"))
    }
}
