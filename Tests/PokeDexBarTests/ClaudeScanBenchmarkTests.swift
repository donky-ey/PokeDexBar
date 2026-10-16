import XCTest
@testable import PokeDexBar

/// 큰 Claude 세션 로그에서 새로고침 비용을 잰다(업스트림 이슈 #337). 기본 실행에서는 건너뛴다 —
/// 100MB 합성 파일을 만들고 시간을 재므로 CI·일상 스위트에는 맞지 않는다.
///
///     PTB_BENCH=1 swift test --filter ClaudeScanBenchmarkTests
///
/// 재는 것: ① 콜드 파싱 ② 활성 파일에 한 줄 덧붙인 뒤의 새로고침(이슈의 정상 상태 비용) ③ 변경 없는 새로고침.
/// 합성 줄은 실제 transcript 처럼 user·tool_result·assistant 가 섞이고, 사용량 줄은 셋 중 하나다.
final class ClaudeScanBenchmarkTests: XCTestCase {
    func testRefreshCostOnALargeActiveSessionLog() async throws {
        guard ProcessInfo.processInfo.environment["PTB_BENCH"] == "1" else {
            throw XCTSkip("set PTB_BENCH=1 to run the Claude scan benchmark")
        }
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("claude-bench-\(UUID().uuidString)")
        let root = base.appendingPathComponent("projects/p")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let session = root.appendingPathComponent("session.jsonl")

        let targetBytes = 100 * 1024 * 1024
        let filler = String(repeating: "lorem ipsum dolor sit amet ", count: 40)   // ≈1KB 본문
        var written = 0
        var turn = 0
        FileManager.default.createFile(atPath: session.path, contents: nil)
        let handle = try FileHandle(forWritingTo: session)
        while written < targetBytes {
            var chunk = ""
            for _ in 0..<1000 {
                turn += 1
                chunk += Self.userLine(turn, filler) + "\n"
                chunk += Self.toolLine(turn, filler) + "\n"
                chunk += Self.assistantLine(turn) + "\n"
            }
            let data = Data(chunk.utf8)
            handle.write(data)
            written += data.count
        }
        try handle.close()

        let cache = LocalUsageCache(claudeRoot: root.deletingLastPathComponent(),
                                    fileURL: base.appendingPathComponent("usage-cache.json"))
        let since = Date(timeIntervalSince1970: 0)

        let peakBefore = Self.peakFootprintMB()
        var clock = ContinuousClock.now
        let cold = await cache.claudeEntries(modifiedSince: since)
        let coldTime = ContinuousClock.now - clock
        let peakAfterCold = Self.peakFootprintMB()

        let append = try FileHandle(forWritingTo: session)
        try append.seekToEnd()
        append.write(Data((Self.assistantLine(turn + 1) + "\n").utf8))
        try append.close()
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)],
                                              ofItemAtPath: session.path)

        clock = ContinuousClock.now
        let grown = await cache.claudeEntries(modifiedSince: since)
        let appendTime = ContinuousClock.now - clock

        clock = ContinuousClock.now
        _ = await cache.claudeEntries(modifiedSince: since)
        let unchangedTime = ContinuousClock.now - clock

        XCTAssertEqual(grown.count, cold.count + 1)
        print(String(format: "BENCH claude %dMB lines=%d usage=%d cold=%.0fms append-refresh=%.0fms unchanged=%.1fms peak-footprint-before=%dMB after-cold=%dMB",
                     written / 1024 / 1024, turn * 3, cold.count,
                     Self.ms(coldTime), Self.ms(appendTime), Self.ms(unchangedTime),
                     peakBefore, peakAfterCold))
    }

    /// 프로세스 수명 동안의 최대 메모리 풋프린트(MB). 콜드 파싱 직전·직후 값을 비교해 파싱이 올린 피크를 본다.
    private static func peakFootprintMB() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return -1 }
        return Int(info.ledger_phys_footprint_peak / 1024 / 1024)
    }

    private static func ms(_ d: Duration) -> Double {
        Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
    }

    private static func stamp(_ turn: Int) -> String {
        let seconds = 1_790_000_000 + turn * 7
        let date = Date(timeIntervalSince1970: TimeInterval(seconds))
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }

    private static func userLine(_ turn: Int, _ text: String) -> String {
        #"{"type":"user","timestamp":"\#(stamp(turn))","message":{"role":"user","content":"\#(text)"},"uuid":"u\#(turn)"}"#
    }

    private static func toolLine(_ turn: Int, _ text: String) -> String {
        #"{"type":"user","timestamp":"\#(stamp(turn))","message":{"role":"user","content":[{"type":"tool_result","content":"\#(text)"}]},"uuid":"t\#(turn)"}"#
    }

    private static func assistantLine(_ turn: Int) -> String {
        #"{"type":"assistant","timestamp":"\#(stamp(turn))","requestId":"req_\#(turn)","message":{"id":"msg_\#(turn)","model":"claude-opus-5-5","role":"assistant","content":[{"type":"text","text":"ok"}],"usage":{"input_tokens":12,"output_tokens":340,"cache_creation_input_tokens":1200,"cache_read_input_tokens":45000}},"uuid":"a\#(turn)"}"#
    }
}
