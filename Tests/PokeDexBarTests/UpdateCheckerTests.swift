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

    // MARK: - Cooldown stamps only after a successful, validated check (upstream #321)

    private static let releaseURL = "https://github.com/donky-ey/PokeDexBar/releases/tag/v2.5.5"

    @MainActor
    private func isolatedDefaults() -> UserDefaults {
        let suite = "UpdateCheckerTests.check.\(UUID().uuidString)"
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        return UserDefaults(suiteName: suite)!
    }

    /// A failed GitHub lookup must not start the 30-minute cooldown: otherwise opening the
    /// popover again stays silent until the timer expires, even though no release was seen.
    @MainActor
    func testFailedCheckDoesNotStartTheCooldown() async {
        var now = Date(timeIntervalSince1970: 1_700_000_000)
        var fetches = 0
        let checker = UpdateChecker(currentVersion: "2.5.3", clock: { now }, defaults: isolatedDefaults()) {
            fetches += 1
            return nil
        }

        await checker.check(minInterval: 1_800)
        XCTAssertEqual(fetches, 1)
        XCTAssertNil(checker.available)

        now = now.addingTimeInterval(5)
        await checker.check(minInterval: 1_800)
        XCTAssertEqual(fetches, 2, "a failed check must not suppress the next attempt")
    }

    @MainActor
    func testSuccessfulCheckStartsTheCooldownAndAppliesTheRelease() async {
        var now = Date(timeIntervalSince1970: 1_700_000_000)
        var fetches = 0
        let checker = UpdateChecker(currentVersion: "2.5.3", clock: { now }, defaults: isolatedDefaults()) {
            fetches += 1
            return UpdateChecker.LatestRelease(tag: "v2.5.5", url: Self.releaseURL)
        }

        await checker.check(minInterval: 1_800)
        XCTAssertEqual(fetches, 1)
        XCTAssertEqual(checker.available?.version, "2.5.5")
        XCTAssertEqual(checker.available?.url, Self.releaseURL)

        now = now.addingTimeInterval(60)
        await checker.check(minInterval: 1_800)
        XCTAssertEqual(fetches, 1, "a successful check must honour minInterval")

        now = now.addingTimeInterval(1_800)
        await checker.check(minInterval: 1_800)
        XCTAssertEqual(fetches, 2, "after the cooldown the next check must fetch again")
    }

    @MainActor
    func testRejectedReleaseUrlDoesNotStartTheCooldown() async {
        var fetches = 0
        let checker = UpdateChecker(currentVersion: "2.5.3", clock: { Date(timeIntervalSince1970: 1_700_000_000) },
                                    defaults: isolatedDefaults()) {
            fetches += 1
            return UpdateChecker.LatestRelease(tag: "v2.5.5", url: "http://evil.example/x")
        }

        await checker.check(minInterval: 1_800)
        XCTAssertNil(checker.available)
        await checker.check(minInterval: 1_800)
        XCTAssertEqual(fetches, 2, "an unsafe URL is a failed check, not a cooldown start")
    }

    /// Malformed tags and unsupported prerelease tags are failed checks: nothing is applied, and the
    /// very next attempt fetches again and applies a valid release instead of waiting 30 minutes.
    @MainActor
    func testMalformedOrPrereleaseTagIsAFailedCheckAndDoesNotBlockTheNextOne() async {
        let badTags = ["", "latest", "v", "v2.5", "2.5.5.1", "v2..5", "2.5.x", "release-2.5.5", "v 2.5.5",
                       "v2.6.0-beta.1", "2.6.0-rc1", "v2.6.0+build.5", "v2.6.0.beta", "v-2.6.0",
                       "v1234567890.0.0", "v٢.٥.٥"]
        for bad in badTags {
            var tag = bad
            var fetches = 0
            let checker = UpdateChecker(currentVersion: "2.5.3", clock: { Date(timeIntervalSince1970: 1_700_000_000) },
                                        defaults: isolatedDefaults()) {
                fetches += 1
                return UpdateChecker.LatestRelease(tag: tag, url: Self.releaseURL)
            }

            await checker.check(minInterval: 1_800)
            XCTAssertNil(checker.available, "\(bad.debugDescription) must not be offered")
            XCTAssertEqual(checker.settingsNotice, .current, "\(bad.debugDescription)")

            tag = "v2.5.5"
            await checker.check(minInterval: 1_800)
            XCTAssertEqual(fetches, 2, "\(bad.debugDescription) must not start the cooldown")
            XCTAssertEqual(checker.available?.version, "2.5.5", "the next valid release applies at once")
        }
    }

    func testNormalizedReleaseVersion() {
        XCTAssertEqual(UpdateChecker.normalizedReleaseVersion("v2.5.5"), "2.5.5")
        XCTAssertEqual(UpdateChecker.normalizedReleaseVersion("2.5.10"), "2.5.10")
        XCTAssertEqual(UpdateChecker.normalizedReleaseVersion(" V2.05.10\n"), "2.5.10", "trimmed, prefix and leading zeros dropped")
        XCTAssertNil(UpdateChecker.normalizedReleaseVersion("v2.6.0-beta.1"))
        XCTAssertNil(UpdateChecker.normalizedReleaseVersion("v2.5"))
        XCTAssertNil(UpdateChecker.normalizedReleaseVersion("v1234567890.0.0"), "component would overflow comparisons")
    }

    /// 겹친 확인은 조회 하나를 **나눠 쓴다** — 두 번째 호출자도 그 결과를 기다려 본다.
    ///
    /// 업스트림 #321 은 진행 중이면 그냥 돌아왔다. 포크에선 그게 퇴행이다: 팝오버 열림이 시작한 조회가 도는
    /// 동안 설정의 "지금 확인"(`minInterval: 0`)을 누르면 즉시 돌아와, 첫 조회가 끝날 때까지(느린 망에서 최대
    /// 15초) "최신 버전"을 보였다. main 에서는 수동 확인이 늘 자기 조회를 기다렸다(리뷰 지적).
    @MainActor
    func testOverlappingChecksShareOneFetch() async {
        var fetches = 0
        var release: CheckedContinuation<Void, Never>?
        let checker = UpdateChecker(currentVersion: "2.5.3", defaults: isolatedDefaults()) {
            fetches += 1
            if fetches == 1 { await withCheckedContinuation { release = $0 } }
            return UpdateChecker.LatestRelease(tag: "v2.5.5", url: Self.releaseURL)
        }
        let first = Task { await checker.check(minInterval: 1_800) }
        while release == nil { await Task.yield() }

        var secondReturned = false
        let second = Task {
            await checker.check(minInterval: 0)
            secondReturned = true
        }
        for _ in 0..<50 { await Task.yield() }
        XCTAssertFalse(secondReturned, "the overlapping caller must wait for the in-flight fetch, not return early")
        XCTAssertEqual(fetches, 1, "a check while one is in flight does not start a second fetch")

        release?.resume()
        await first.value
        await second.value
        XCTAssertTrue(secondReturned)
        XCTAssertEqual(fetches, 1)
        XCTAssertEqual(checker.available?.version, "2.5.5", "the waiting caller sees the shared result")
    }

    /// 진행 중이던 조회가 실패하면 다음 확인은 새로 조회한다(실패는 쿨다운을 시작하지 않는다).
    @MainActor
    func testAFailedInFlightCheckLetsTheNextOneFetch() async {
        var fetches = 0
        var release: CheckedContinuation<Void, Never>?
        let checker = UpdateChecker(currentVersion: "2.5.3", defaults: isolatedDefaults()) {
            fetches += 1
            if fetches == 1 { await withCheckedContinuation { release = $0 } }
            return nil
        }
        let first = Task { await checker.check(minInterval: 1_800) }
        while release == nil { await Task.yield() }
        release?.resume()
        await first.value
        await checker.check(minInterval: 1_800)
        XCTAssertEqual(fetches, 2, "once the in-flight check finished (failed), the next one fetches")
    }
}
