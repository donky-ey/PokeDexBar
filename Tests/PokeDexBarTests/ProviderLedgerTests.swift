import XCTest
@testable import PokeDexBar

/// 진행 적립 장부는 프로바이더마다 따로 고점을 기억한다(업스트림 #143, 포크 모양).
///
/// 합산 고점 하나로 비교하던 시절에는 한 프로바이더의 오늘 합계가 줄거나(중복 제거·미러 행 제외·부분
/// 스캔) 빠지면, **모든 프로바이더의** 지갑·경험치·알 진행이 그 고점을 다시 넘을 때까지 멈췄다 — 자정에
/// 저절로 풀려서 아무도 몰랐다. 업스트림은 떨어진 프로바이더의 기준을 낮추지만(rebase), 그러면 일시적으로
/// 떨어졌다가 돌아온 같은 사용량을 두 번 준다. 포크는 **떨어진 프로바이더만 자기 고점에서 기다린다.**
@MainActor
final class ProviderLedgerTests: XCTestCase {
    private var file: URL!
    private var suite: String!

    override func setUp() {
        super.setUp()
        file = FileManager.default.temporaryDirectory.appendingPathComponent("ledger-\(UUID().uuidString).json")
        suite = "ledger-\(UUID().uuidString)"
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: file)
        UserDefaults().removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private var defaults: UserDefaults { UserDefaults(suiteName: suite)! }

    private func makeStore() -> PlayerStore {
        PlayerStore(fileURL: file, rng: SeededRNG(seed: 3), defaults: defaults)
    }

    /// 지갑 변화량 — 부적이 없으니 적립 델타와 같다.
    private func earned(_ store: PlayerStore, after body: () -> Void) -> Int {
        let before = store.state.earnedTokens
        body()
        return store.state.earnedTokens - before
    }

    private let day = "2026-10-16"

    // MARK: 프로바이더별 고점

    func testADropInOneProviderDoesNotFreezeTheOthers() {
        let store = makeStore()
        store.update(todayTokensByProvider: ["claude_code": 1_000, "codex": 500], todayDate: day, hasUsageData: true)
        let gained = earned(store) {
            store.update(todayTokensByProvider: ["claude_code": 1_500, "codex": 200], todayDate: day, hasUsageData: true)
        }
        XCTAssertEqual(gained, 500, "Claude's growth must be credited even though Codex's total dropped")
    }

    /// 포크가 업스트림과 다르게 가는 지점 — 기준을 낮추면 돌아온 같은 사용량을 다시 준다.
    func testATransientDipIsNotPaidTwice() {
        let store = makeStore()
        store.update(todayTokensByProvider: ["claude_code": 1_000], todayDate: day, hasUsageData: true)
        XCTAssertEqual(earned(store) {
            store.update(todayTokensByProvider: ["claude_code": 400], todayDate: day, hasUsageData: true)
            store.update(todayTokensByProvider: ["claude_code": 1_000], todayDate: day, hasUsageData: true)
        }, 0, "a dip and recovery is the same usage, not new usage")
        XCTAssertEqual(earned(store) {
            store.update(todayTokensByProvider: ["claude_code": 1_100], todayDate: day, hasUsageData: true)
        }, 100)
    }

    func testAProviderMissingFromARefreshKeepsItsBaseline() {
        let store = makeStore()
        store.update(todayTokensByProvider: ["claude_code": 1_000, "codex": 500], todayDate: day, hasUsageData: true)
        XCTAssertEqual(earned(store) {
            store.update(todayTokensByProvider: ["claude_code": 1_200], todayDate: day, hasUsageData: true)
        }, 200)
        XCTAssertEqual(earned(store) {
            store.update(todayTokensByProvider: ["claude_code": 1_200, "codex": 700], todayDate: day, hasUsageData: true)
        }, 200, "Codex resumes from its own baseline (500), not from zero")
    }

    func testANewProviderIsSeededNotBackPaid() {
        let store = makeStore()
        store.update(todayTokensByProvider: ["claude_code": 1_000], todayDate: day, hasUsageData: true)
        XCTAssertEqual(earned(store) {
            store.update(todayTokensByProvider: ["claude_code": 1_000, "codex": 5_000], todayDate: day, hasUsageData: true)
        }, 0, "the first sighting of a provider is its baseline")
        XCTAssertEqual(earned(store) {
            store.update(todayTokensByProvider: ["claude_code": 1_000, "codex": 5_600], todayDate: day, hasUsageData: true)
        }, 600)
    }

    /// 날짜가 바뀌면 오늘 누적값 전부가 새 사용량이다 — 알던 프로바이더는 0 에서 다시 연다.
    func testANewDayPaysEveryProviderFromZero() {
        let store = makeStore()
        store.update(todayTokensByProvider: ["claude_code": 9_000, "codex": 500], todayDate: day, hasUsageData: true)
        XCTAssertEqual(earned(store) {
            store.update(todayTokensByProvider: ["claude_code": 300], todayDate: "2026-10-17", hasUsageData: true)
        }, 300)
        XCTAssertEqual(earned(store) {
            store.update(todayTokensByProvider: ["claude_code": 300, "codex": 200], todayDate: "2026-10-17",
                         hasUsageData: true)
        }, 200, "Codex was known yesterday, so today's first sighting is paid from zero")
    }

    func testABaselineNeedsProviderData() {
        let store = makeStore()
        store.update(todayTokensByProvider: [:], todayDate: day, hasUsageData: true)
        XCTAssertFalse(store.state.installBaselineSet, "snapshots without a today figure are not a baseline")
        store.update(todayTokensByProvider: ["claude_code": 700], todayDate: day, hasUsageData: true)
        XCTAssertTrue(store.state.installBaselineSet)
        XCTAssertEqual(store.state.earnedTokens, 0, "usage before the baseline is not credited")
    }

    // MARK: 1.19.0 세이브에서 넘어오기

    /// 1.19.0 이 쓰던 세이브 모양 — 현재 인코더 출력에서 새 필드를 빼고 옛 합산 장부를 넣는다(손으로 상상한
    /// 모양이 아니라 실제 인코더가 쓰는 키 위에서 만든다). 봉인까지 1.19.0 처럼 씌운다.
    private func writeSealedOldSave(claimed: Int, lastDate: String, earned: Int) throws {
        var state = PlayerState()
        state.installBaselineSet = true
        state.lastDate = lastDate
        state.earnedTokens = earned
        let encoded = try JSONEncoder().encode(state)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertNotNil(json["claimedTodayTokensByProvider"], "the current encoder writes the new ledger")
        json.removeValue(forKey: "claimedTodayTokensByProvider")
        json["claimedTodayTokens"] = claimed
        let payload = try JSONSerialization.data(withJSONObject: json)
        try SaveSeal.seal(payload).write(to: file)
        defaults.set(true, forKey: PlayerStore.sealedKey)   // 1.19.0 이 이미 봉인 세이브를 쓴 기기
    }

    func testAnOldSealedSaveLoadsUntamperedAndPaysOnlyTheRestOfTheDay() throws {
        try writeSealedOldSave(claimed: 1_000, lastDate: day, earned: 42_000)
        let store = makeStore()
        XCTAssertFalse(store.state.tampered, "adding a ledger field must not flip an existing seal to tampered")
        XCTAssertEqual(store.state.earnedTokens, 42_000)

        XCTAssertEqual(earned(store) {
            store.update(todayTokensByProvider: ["claude_code": 1_500, "codex": 300], todayDate: day, hasUsageData: true)
        }, 800, "the old aggregate (1,000) is honoured once: only the rest of the day is new")
        XCTAssertEqual(earned(store) {
            store.update(todayTokensByProvider: ["claude_code": 1_600, "codex": 300], todayDate: day, hasUsageData: true)
        }, 100, "after the one-time migration the ledger is per provider")
        XCTAssertNil(store.state.claimedTodayTokensByProvider[PlayerState.legacyAggregateLedgerKey])

        let reloaded = makeStore()   // 새 형식으로 다시 봉인돼 저장됐다 — 그것도 조작이 아니다
        XCTAssertFalse(reloaded.state.tampered)
        XCTAssertEqual(reloaded.state.claimedTodayTokensByProvider, ["claude_code": 1_600, "codex": 300])
    }

    func testAnOldSaveFromAnEarlierDayPaysTheWholeDay() throws {
        try writeSealedOldSave(claimed: 9_000, lastDate: "2026-10-15", earned: 0)
        let store = makeStore()
        XCTAssertEqual(earned(store) {
            store.update(todayTokensByProvider: ["claude_code": 400], todayDate: day, hasUsageData: true)
        }, 400)
    }

    // MARK: 신뢰 경계

    /// 원장 수치는 산술에 쓰인다 — `Int.min`·음수가 그대로 들어오면 뺄셈이 오버플로 트랩으로 프로세스를 죽이고,
    /// 같은 세이브를 읽는 재기동마다 다시 죽는다. 디코드 경계에서 자른다.
    func testLedgerValuesAreClampedAtTheTrustBoundary() throws {
        var state = PlayerState()
        state.installBaselineSet = true
        state.lastDate = day
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        json["claimedTodayTokensByProvider"] = ["claude_code": Int.min, "codex": Int.max]
        let decoded = try JSONDecoder().decode(PlayerState.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded.claimedTodayTokensByProvider["claude_code"], 0)
        XCTAssertEqual(decoded.claimedTodayTokensByProvider["codex"], PlayerState.maxLedgerTokens)

        try SaveSeal.seal(JSONSerialization.data(withJSONObject: json)).write(to: file)
        defaults.set(true, forKey: PlayerStore.sealedKey)
        let store = makeStore()
        store.update(todayTokensByProvider: ["claude_code": Int.max, "codex": Int.max], todayDate: day,
                     hasUsageData: true)   // 트랩 없이 끝나야 한다
        XCTAssertGreaterThanOrEqual(store.state.earnedTokens, 0)
    }
}
