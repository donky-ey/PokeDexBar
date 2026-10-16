import Foundation
import XCTest

// Waiting for asynchronous UI state (a SwiftUI update, an animation, a sleep inside `.task`).
//
// Wait for the state itself, never for a fixed time. How long it takes is not the code's to decide:
// it grows with the main run loop's queue, and inside the full suite that queue holds work left by
// earlier tests. `SessionKeySettingsRenderingTests` slept 500 ms for a scroll that takes ~0.45 s on
// its own and 0.58–1.03 s inside the suite with coverage — it failed one gate run in two.
//
// These return as soon as the condition holds, so the generous timeout only costs time on failure.

/// For async tests: `RunLoop.run` is unavailable there, so sleeping hands the main actor back to the UI.
@MainActor
func waitUntil(timeout: Duration = .seconds(10), _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        guard ContinuousClock.now < deadline else { return false }
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

/// Fixed waits live only in the helpers above, or carry their reason on the same line.
///
/// Some cannot be conditions: a control that shows something did *not* happen needs a window,
/// and a sampler needs an interval. Those say so with `fixed-wait:` — anything else waiting for
/// UI state with a fixed time is the class that made the session key test flaky.
final class FixedWaitGuardTests: XCTestCase {
    func testFixedWaitsLiveOnlyInTheWaitHelpersOrSayWhy() throws {
        let tests = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let primitive = try NSRegularExpression(
            pattern: #"Task\.sleep|Thread\.sleep|usleep\(|\.run\(until:|\.run\(mode:"#)
        let files = try XCTUnwrap(FileManager.default.enumerator(at: tests, includingPropertiesForKeys: nil))
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" && $0.lastPathComponent != "Waiting.swift" }
        XCTAssertGreaterThan(files.count, 100, "the scan is not looking at the test sources")
        var offenders: [String] = []
        for file in files {
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
            for (index, line) in lines.enumerated() {
                // Words inside comments do not count: a comment may describe a wait it does not make.
                let code = line.components(separatedBy: "//")[0]
                let range = NSRange(code.startIndex..., in: code)
                if primitive.firstMatch(in: code, range: range) != nil, !line.contains("fixed-wait:") {
                    offenders.append("\(file.lastPathComponent):\(index + 1)")
                }
            }
        }
        XCTAssertEqual(offenders, [], """
            Fixed wait outside Waiting.swift. Wait for the state with waitUntil / pumpRunLoop(until:); \
            if it truly cannot be a condition, say why on the same line with `fixed-wait:`.
            """)
    }
}
