import XCTest
@testable import PokeDexBar

final class LogRepeatSuppressorTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)
    private let hour: TimeInterval = 3600

    func testFirstObservationIsAlwaysWritten() {
        var suppressor = LogRepeatSuppressor()
        XCTAssertTrue(suppressor.shouldWrite(key: "codex", message: "not found",
                                             now: start, repeatAfter: hour))
    }

    func testIdenticalRepeatIsSuppressed() {
        var suppressor = LogRepeatSuppressor()
        _ = suppressor.shouldWrite(key: "codex", message: "not found", now: start, repeatAfter: hour)
        XCTAssertFalse(suppressor.shouldWrite(key: "codex", message: "not found",
                                              now: start.addingTimeInterval(120), repeatAfter: hour))
    }

    /// A state change is never lost: if suppression swallowed it, the log would lie.
    func testAChangedMessageIsWrittenImmediately() {
        var suppressor = LogRepeatSuppressor()
        _ = suppressor.shouldWrite(key: "codex", message: "not found", now: start, repeatAfter: hour)
        XCTAssertTrue(suppressor.shouldWrite(key: "codex", message: "found: 1.2.3",
                                             now: start.addingTimeInterval(1), repeatAfter: hour))
    }

    /// An unchanged state is still written once per interval, so the log can tell "since when" from
    /// "still true now" — and a quiet log from a dead app.
    func testTheSameStateIsReaffirmedAfterTheInterval() {
        var suppressor = LogRepeatSuppressor()
        _ = suppressor.shouldWrite(key: "codex", message: "not found", now: start, repeatAfter: hour)
        XCTAssertFalse(suppressor.shouldWrite(key: "codex", message: "not found",
                                              now: start.addingTimeInterval(hour - 1), repeatAfter: hour))
        XCTAssertTrue(suppressor.shouldWrite(key: "codex", message: "not found",
                                             now: start.addingTimeInterval(hour), repeatAfter: hour))
    }

    /// The interval restarts after a reaffirmation; otherwise, once passed, every repeat would pass.
    func testTheIntervalRestartsAfterAReaffirmation() {
        var suppressor = LogRepeatSuppressor()
        _ = suppressor.shouldWrite(key: "codex", message: "x", now: start, repeatAfter: hour)
        _ = suppressor.shouldWrite(key: "codex", message: "x", now: start.addingTimeInterval(hour), repeatAfter: hour)
        XCTAssertFalse(suppressor.shouldWrite(key: "codex", message: "x",
                                              now: start.addingTimeInterval(hour + 60), repeatAfter: hour))
    }

    /// Keys are independent: one provider's change must not lift another provider's suppression.
    func testKeysAreIndependent() {
        var suppressor = LogRepeatSuppressor()
        _ = suppressor.shouldWrite(key: "codex", message: "not found", now: start, repeatAfter: hour)
        _ = suppressor.shouldWrite(key: "antigravity", message: "not found", now: start, repeatAfter: hour)

        XCTAssertTrue(suppressor.shouldWrite(key: "codex", message: "found",
                                             now: start.addingTimeInterval(1), repeatAfter: hour))
        XCTAssertFalse(suppressor.shouldWrite(key: "antigravity", message: "not found",
                                              now: start.addingTimeInterval(1), repeatAfter: hour),
                       "another key's change lifted this key's suppression")
    }

    /// 성공 복귀 후 같은 오류의 **재발은 새 사건**이다 — reset 없이는 "오류→성공→같은 오류"의
    /// 두 번째 오류가 1시간 억제창에 삼켜져, 로그만 보면 내내 죽어 있던 것과 구분이 안 된다.
    func testResetMakesTheNextSameErrorANewIncident() {
        var suppressor = LogRepeatSuppressor()
        _ = suppressor.shouldWrite(key: "claude-limits", message: "limits unavailable: timeout",
                                   now: start, repeatAfter: hour)
        suppressor.reset(key: "claude-limits")   // 성공 경로가 부른다
        XCTAssertTrue(suppressor.shouldWrite(key: "claude-limits",
                                             message: "limits unavailable: timeout",
                                             now: start.addingTimeInterval(300), repeatAfter: hour),
                      "성공 뒤 재발한 같은 오류가 반복으로 억제됨")
    }

    /// 대조군 — reset 은 그 키만 잊는다. 전체를 비우면 다른 프로바이더의 반복이 샌다.
    func testResetLeavesOtherKeysSuppressed() {
        var suppressor = LogRepeatSuppressor()
        _ = suppressor.shouldWrite(key: "codex", message: "not found", now: start, repeatAfter: hour)
        suppressor.reset(key: "claude-limits")
        XCTAssertFalse(suppressor.shouldWrite(key: "codex", message: "not found",
                                              now: start.addingTimeInterval(60), repeatAfter: hour))
    }
}
