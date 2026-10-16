import XCTest
@testable import PokeDexBar

/// 자라는 Claude 세션 로그는 덧붙은 꼬리만 파싱한다(업스트림 이슈 #337).
///
/// 활성 세션 파일은 수백 MB 까지 자라고 매 새로고침마다 바뀐다. `(path, mtime, size)` 캐시만으로는 그
/// 파일을 매번 0바이트부터 다시 읽어 — 100MB 합성 파일에서 새로고침 한 번이 11초였다 — 큰 히스토리의
/// 사용자에게 CPU 를 계속 점유한다. 이 파일은 "꼬리만 읽는다"와 "그래도 합계는 전체 파싱과 같다"를 함께 잠근다.
final class ClaudeIncrementalParseTests: XCTestCase {
    private var base: URL!
    private var root: URL!
    private var file: URL!
    private var cacheFile: URL!
    private let since = Date(timeIntervalSince1970: 0)
    private var clock = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970) - 3600)

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("ptb-incr-\(UUID().uuidString)")
        root = base.appendingPathComponent("projects/p")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        file = root.appendingPathComponent("s.jsonl")
        cacheFile = base.appendingPathComponent("usage-cache.json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: base)
    }

    private func line(_ id: String, output: Int) -> String {
        #"{"type":"assistant","requestId":"r-\#(id)","timestamp":"2026-07-02T01:00:00.000Z","message":{"id":"m-\#(id)","model":"claude-opus-4-8","usage":{"input_tokens":10,"output_tokens":\#(output),"cache_creation_input_tokens":5,"cache_read_input_tokens":100}}}"#
    }

    /// 실제 transcript 처럼 사용량이 없는 줄도 섞는다 — 꼬리 경계가 그런 줄 사이에 떨어져도 맞아야 한다.
    private func noise(_ n: Int) -> String {
        #"{"type":"user","timestamp":"2026-07-02T01:00:00.000Z","message":{"role":"user","content":"https://example.com/\#(n) — 한글 본문"}}"#
    }

    /// 파일을 통째로 쓰고 mtime 을 앞으로 민다(같은 초 안의 두 번째 쓰기도 변경으로 보이게).
    private func write(_ text: String) throws {
        try Data(text.utf8).write(to: file)
        clock = clock.addingTimeInterval(10)
        try FileManager.default.setAttributes([.modificationDate: clock], ofItemAtPath: file.path)
    }

    private func append(_ text: String) throws {
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        handle.write(Data(text.utf8))
        try handle.close()
        clock = clock.addingTimeInterval(10)
        try FileManager.default.setAttributes([.modificationDate: clock], ofItemAtPath: file.path)
    }

    private func makeCache() -> LocalUsageCache {
        LocalUsageCache(claudeRoot: base.appendingPathComponent("projects"), fileURL: cacheFile)
    }

    /// id → 출력. 같은 id 가 두 번 나오면(합칠 때 dedup 이 빠지면) 값 대신 -1 로 표시해 단언이 깨지게 한다.
    private func outputs(_ entries: [LocalUsageReader.Entry]) -> [String: Int] {
        Dictionary(entries.map { ($0.id, $0.output) }, uniquingKeysWith: { _, _ in -1 })
    }

    // MARK: 꼬리만 읽는다

    func testAppendedLinesAreParsedFromTheSavedOffset() async throws {
        try write(line("1", output: 111) + "\n" + noise(1) + "\n")
        let cache = makeCache()
        _ = await cache.claudeEntries(modifiedSince: since)
        let firstSize = try XCTUnwrap(try file.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        let firstScan = await cache.claudeBytesParsedInLastScan()
        XCTAssertEqual(firstScan, firstSize, "the first scan reads the whole file")

        let tail = line("2", output: 222) + "\n"
        try append(tail)
        let entries = await cache.claudeEntries(modifiedSince: since)
        let secondScan = await cache.claudeBytesParsedInLastScan()
        XCTAssertEqual(outputs(entries), ["m-1|r-1": 111, "m-2|r-2": 222])
        XCTAssertEqual(secondScan, Data(tail.utf8).count, "only the appended tail is read")

        _ = await cache.claudeEntries(modifiedSince: since)
        let thirdScan = await cache.claudeBytesParsedInLastScan()
        XCTAssertEqual(thirdScan, 0, "an unchanged file is not read at all")
    }

    /// 스트리밍 중인 응답은 같은 id 가 출력이 커지며 여러 줄에 나온다 — 경계를 넘어가도 최댓값 하나만 남는다.
    func testAStreamingTurnThatCrossesTheBoundaryKeepsItsLargestLine() async throws {
        try write(line("1", output: 10) + "\n")
        let cache = makeCache()
        _ = await cache.claudeEntries(modifiedSince: since)
        try append(line("1", output: 50) + "\n")
        let entries = await cache.claudeEntries(modifiedSince: since)
        XCTAssertEqual(outputs(entries), ["m-1|r-1": 50])
    }

    /// 쓰는 중인 마지막 줄(개행 없음)은 오프셋에 넣지 않는다 — 다 쓰인 뒤 다시 읽힌다.
    func testHalfWrittenLastLineWaitsForItsNewline() async throws {
        let full = line("2", output: 222)
        try write(line("1", output: 111) + "\n" + String(full.prefix(full.count / 2)))
        let cache = makeCache()
        let first = await cache.claudeEntries(modifiedSince: since)
        XCTAssertEqual(outputs(first), ["m-1|r-1": 111], "a cut-off JSON line is not an entry")

        try append(String(full.dropFirst(full.count / 2)) + "\n")
        let second = await cache.claudeEntries(modifiedSince: since)
        XCTAssertEqual(outputs(second), ["m-1|r-1": 111, "m-2|r-2": 222])
    }

    /// 개행 없이 끝난 마지막 줄은 매번 다시 읽힌다 — 합칠 때 dedup 하지 않으면 그 줄이 저장된 blob 에
    /// 새로고침마다 하나씩 쌓인다. 반환값은 끝에서 한 번 더 dedup 되므로 blob 자체를 본다.
    func testMergedBlobsDoNotAccumulateDuplicates() async throws {
        let ticks = Ticker()
        let cache = LocalUsageCache(claudeRoot: base.appendingPathComponent("projects"), fileURL: cacheFile,
                                    now: { ticks.next() })   // 매 호출 61초씩 — 60초 저장 throttle 을 넘긴다
        try write(line("1", output: 111) + "\n" + line("2", output: 222))
        _ = await cache.claudeEntries(modifiedSince: since)
        try append("\n" + line("3", output: 333))
        _ = await cache.claudeEntries(modifiedSince: since)

        let raw = try Data(contentsOf: cacheFile)
        let plain = (try? (raw as NSData).decompressed(using: .zlib) as Data) ?? raw
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: plain) as? [String: Any])
        let claude = try XCTUnwrap(json["claude"] as? [String: [String: Any]])
        XCTAssertEqual(claude.count, 1)
        let blob = try XCTUnwrap(claude.values.first)   // 키는 열거자의 경로(/private/var…)라 픽스처 경로와 다를 수 있다
        let stored = try XCTUnwrap(blob["entries"] as? [Any])
        XCTAssertEqual(stored.count, 3, "the re-read trailing line must not be stored twice")
    }

    // MARK: 덧붙임이 아니면 처음부터

    func testTruncatedFileIsReparsedFromStart() async throws {
        try write(line("1", output: 111) + "\n" + line("2", output: 222) + "\n")
        let cache = makeCache()
        _ = await cache.claudeEntries(modifiedSince: since)
        try write(line("3", output: 333) + "\n")
        let entries = await cache.claudeEntries(modifiedSince: since)
        XCTAssertEqual(outputs(entries), ["m-3|r-3": 333])
    }

    func testSameSizeRewriteIsReparsed() async throws {
        try write(line("1", output: 111) + "\n")
        let cache = makeCache()
        _ = await cache.claudeEntries(modifiedSince: since)
        try write(line("1", output: 999) + "\n")
        let entries = await cache.claudeEntries(modifiedSince: since)
        XCTAssertEqual(outputs(entries), ["m-1|r-1": 999])
    }

    /// 복사·재기록 경로(CLAUDE.md) — 자라기만 한 것처럼 보여도 앞부분이 다시 쓰였으면 꼬리만 읽으면 안 된다.
    /// 오프셋 바로 앞 바이트의 지문이 달라지면 처음부터 읽는다.
    func testARewrittenPrefixIsReparsedEvenWhenTheFileGrew() async throws {
        try write(line("1", output: 111) + "\n")
        let cache = makeCache()
        _ = await cache.claudeEntries(modifiedSince: since)
        try write(line("1", output: 777) + "\n" + line("2", output: 222) + "\n")
        let entries = await cache.claudeEntries(modifiedSince: since)
        XCTAssertEqual(outputs(entries), ["m-1|r-1": 777, "m-2|r-2": 222],
                       "a rewritten prefix must not keep the stale cached value")
    }

    // MARK: 합계는 전체 파싱과 같다

    /// Review Focus — 증분으로 여러 번 나눠 읽은 결과가 같은 파일을 한 번에 읽은 결과와 정확히 같다.
    func testIncrementalResultMatchesAFullParse() async throws {
        try write("")
        let cache = makeCache()
        var expected = ""
        for step in 0..<6 {
            var chunk = ""
            for i in 0..<5 {
                let n = step * 5 + i
                chunk += noise(n) + "\n"
                chunk += line("\(n % 7)", output: n * 10) + "\n"   // 같은 id 가 경계를 넘어 다시 나온다
            }
            if step == 3 {   // 한 번은 줄 중간에서 끊긴 채로 새로고침된다
                let cut = chunk.index(chunk.endIndex, offsetBy: -40)
                try append(String(chunk[..<cut]))
                _ = await cache.claudeEntries(modifiedSince: since)
                try append(String(chunk[cut...]))
            } else {
                try append(chunk)
            }
            expected += chunk
            _ = await cache.claudeEntries(modifiedSince: since)
        }
        let incremental = await cache.claudeEntries(modifiedSince: since)
        let full = LocalUsageReader.parseClaudeFile(file, fmt: LocalUsageReader.localDayFormatter())
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), expected)
        XCTAssertEqual(outputs(incremental), outputs(full))
        XCTAssertEqual(Set(incremental.map(\.date)), Set(full.map(\.date)))
    }

    /// 오프셋이 없던 시절의 캐시 파일도 읽힌다 — 그 blob 은 파일이 처음 바뀔 때 전체를 다시 읽는다.
    func testABlobWithoutAnOffsetStillLoads() async throws {
        try write(line("1", output: 111) + "\n")
        _ = await makeCache().claudeEntries(modifiedSince: since)

        let raw = try Data(contentsOf: cacheFile)
        let plain = (try? (raw as NSData).decompressed(using: .zlib) as Data) ?? raw
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: plain) as? [String: Any])
        var claude = try XCTUnwrap(json["claude"] as? [String: [String: Any]])
        XCTAssertFalse(claude.isEmpty)
        for (key, var blob) in claude {
            XCTAssertNotNil(blob["offset"], "the new blob records its offset")
            blob.removeValue(forKey: "offset")
            blob.removeValue(forKey: "boundary")
            claude[key] = blob
        }
        json["claude"] = claude
        try JSONSerialization.data(withJSONObject: json).write(to: cacheFile)

        let reloaded = makeCache()
        let entries = await reloaded.claudeEntries(modifiedSince: since)
        XCTAssertEqual(outputs(entries), ["m-1|r-1": 111], "an old blob is reused while its file is unchanged")
        try append(line("2", output: 222) + "\n")
        let grown = await reloaded.claudeEntries(modifiedSince: since)
        XCTAssertEqual(outputs(grown), ["m-1|r-1": 111, "m-2|r-2": 222])
    }
}

/// 타임스탬프 파서는 모든 로컬 로그의 줄마다 불린다 — 호출마다 포매터를 만들던 것이 콜드 스캔의 주 비용이었다.
final class ISO8601ParserSharingTests: XCTestCase {
    func testTheSharedParserKeepsEveryFormat() {
        let reference = Date(timeIntervalSince1970: 1_783_300_000.123)
        XCTAssertEqual(ISO8601Parser.date(from: "2026-07-06T01:06:40.123Z")!.timeIntervalSince1970,
                       reference.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(ISO8601Parser.date(from: "2026-07-06T01:06:40.123456+00:00")!.timeIntervalSince1970,
                       reference.timeIntervalSince1970, accuracy: 0.001)   // 마이크로초
        XCTAssertEqual(ISO8601Parser.date(from: "2026-07-06T01:06:40Z")!.timeIntervalSince1970,
                       1_783_300_000, accuracy: 0.001)                       // 소수 없음
        XCTAssertNil(ISO8601Parser.date(from: "not a date"))
    }

    /// 공유 포매터는 잠금 뒤에 있다 — 여러 프로바이더 캐시가 동시에 불러도 결과가 섞이거나 죽지 않는다.
    func testConcurrentCallersGetConsistentResults() {
        let inputs = (0..<64).map { "2026-07-06T01:06:\(String(format: "%02d", $0 % 60)).5Z" }
        let expected = inputs.map { ISO8601Parser.date(from: $0) }
        let mismatches = ManagedCounter()
        DispatchQueue.concurrentPerform(iterations: 2000) { i in
            let k = i % inputs.count
            if ISO8601Parser.date(from: inputs[k]) != expected[k] { mismatches.bump() }
        }
        XCTAssertEqual(mismatches.value, 0)
    }
}

private final class Ticker: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_790_000_000)
    func next() -> Date { lock.lock(); defer { lock.unlock() }; current += 61; return current }
}

private final class ManagedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
    func bump() { lock.lock(); count += 1; lock.unlock() }
}
