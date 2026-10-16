import Foundation
import XCTest

// Waiting for asynchronous UI state (a SwiftUI update, an animation, a sleep inside `.task`).
//
// Wait for the state itself, never for a fixed time. How long it takes is not the code's to decide:
// it grows with the main run loop's queue, and inside the full suite that queue holds work left by
// earlier tests. `SessionKeySettingsRenderingTests` slept 500 ms for a scroll that takes ~0.45 s on
// its own and 0.58–1.03 s inside the suite with coverage — it failed one gate run in two.
//
// An absence is usually a condition too: wait for the event at which the thing would have happened
// (a reveal's `onDone`, the first render), then check it did not. Only when no such event exists, or
// when real time is the subject, does a fixed window remain — `pumpRunLoop(for:because:)`.
//
// The condition waits return as soon as the condition holds, so the generous timeout only costs time
// on failure.

/// For async tests: `RunLoop.run` is unavailable there, so sleeping hands the main actor back to the UI.
@MainActor
func waitUntil(timeout: Duration = .seconds(10), _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        // A cancelled task's sleep returns at once; without this the loop would spin the main actor.
        guard ContinuousClock.now < deadline, !Task.isCancelled else { return false }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return true
}

/// For synchronous tests: spins the main run loop so SwiftUI gets to update between checks.
@MainActor @discardableResult
func pumpRunLoop(until condition: () -> Bool, timeout: TimeInterval = 10) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        guard Date() < deadline else { return false }
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
    }
    return true
}

/// Spins the main run loop for a fixed time, for the waits that have no condition: an absence with
/// no event marking when it would have happened, or real time itself (a capture's frame grid).
/// `because` keeps the reason at the call site, where a reviewer reads it.
@MainActor
func pumpRunLoop(for seconds: TimeInterval, because reason: StaticString) {
    precondition(reason.utf8CodeUnitCount > 0, "say why this cannot wait for a condition")
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        RunLoop.current.run(mode: .default, before: min(deadline, Date().addingTimeInterval(0.01)))
    }
}

/// Wait primitives outside this file are a closed list.
///
/// Every sleep or run-loop spin outside `Waiting.swift` must be listed in `allowedPrimitives`, one
/// reason per occurrence, so a new one is an edit here that a reviewer sees. The first version took a
/// `fixed-wait:` marker on the primitive's line instead, and a helper's *definition* could carry it
/// while every caller of that helper stayed invisible (review of #23).
///
/// Not covered: whether a `because:` reason holds up (review's job), waits built on
/// `XCTestExpectation` (one nobody fulfils, or an inverted one, is a fixed window too), and production code.
final class FixedWaitGuardTests: XCTestCase {
    /// The waits the helpers above cannot express: async, or on a thread with no run loop to pump.
    static let allowedPrimitives: [String: [String]] = [
        "AdditionalClaudeAccountsTests.swift": [
            "100 ms showing a manual refresh has not fetched yet: async, and nothing marks when it would have",
        ],
        "AppLogTests.swift": [
            "a slow sink, so a flush that returns before the queued write lands is caught",
            "a slow sink, so a writeAndFlush that returns before the line lands is caught",
        ],
        "CodexLargeRolloutPerformanceTests.swift": [
            "joining the RSS sampler thread, polled on `isFinished`",
            "the RSS sampling interval itself",
        ],
    ]

    func testWaitPrimitivesOutsideTheHelpersAreAClosedList() throws {
        let tests = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let primitive = try NSRegularExpression(
            pattern: #"\.sleep\(|(?<![A-Za-z0-9_.])u?sleep\(|\.run\((until|mode):|CFRunLoopRunInMode\(|asyncAfter\("#)
        let files = try XCTUnwrap(FileManager.default.enumerator(at: tests, includingPropertiesForKeys: nil))
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" && $0.lastPathComponent != "Waiting.swift" }
        XCTAssertGreaterThan(files.count, 100, "the scan is not looking at the test sources")
        var found: [String: Int] = [:]
        for file in files {
            for line in try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n") {
                // Words inside comments do not count: a comment may describe a wait it does not make.
                // `SourceScan` cuts at a real `//`, not at one inside a string such as "https://…".
                let code = SourceScan.code(line)
                let matches = primitive.numberOfMatches(in: code, range: NSRange(code.startIndex..., in: code))
                if matches > 0 { found[file.lastPathComponent, default: 0] += matches }
            }
        }
        XCTAssertEqual(found, Self.allowedPrimitives.mapValues(\.count), """
            A wait primitive outside Waiting.swift. Wait for the state with waitUntil / pumpRunLoop(until:) \
            — an absence included, by waiting for the event at which it would have happened. With no such \
            event use pumpRunLoop(for:because:). Only a wait those cannot express goes into allowedPrimitives.
            """)
    }
}
