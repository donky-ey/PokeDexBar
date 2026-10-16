import XCTest
@testable import PokeDexBar

/// 화면 문구는 `Localization.swift` 를 거친다 — UI 소스에 한글 문자열 리터럴이 있으면 안 된다.
///
/// 문자열 보간 테스트는 이미 `L` 을 거치는 문자열만 본다. 표를 아예 안 거친 리터럴은 구조적으로 안 보인다
/// (업스트림 #210 이 한글 리터럴 세 개를 `Text(...)` 에 바로 넣어, 한국어가 아닌 사용자 전원이 한국어를 읽을
/// 뻔했다 — #222). 그래서 UI 소스 자체를 훑는다. 한글 *주석*은 이 저장소의 관례라 허용하고 문자열 리터럴만 잡는다.
/// 포크는 앱 진입 파일(`PokeDexBarApp.swift`)에도 화면 문구가 있어 함께 본다. Core·Player 는 언어별 데이터
/// 테이블(이름·도감 문구)이 정당하게 한글을 담으므로 대상이 아니다.
final class LocalizedUILiteralTests: XCTestCase {
    func testNoHangulStringLiteralsInUISources() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/PokeDexBar")
        let ui = sources.appendingPathComponent("UI")
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: ui, includingPropertiesForKeys: nil))
        var files = [sources.appendingPathComponent("PokeDexBarApp.swift")]
        for case let url as URL in enumerator where url.pathExtension == "swift" { files.append(url) }
        XCTAssertGreaterThan(files.count, 10, "UI 소스를 못 찾았다 — 경로가 바뀌었으면 이 가드는 아무것도 안 본다")

        var offenders: [String] = []
        for url in files {
            let lines = try String(contentsOf: url, encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            for (index, line) in lines.enumerated() where Self.hasHangulStringLiteral(line) {
                offenders.append("\(url.lastPathComponent):\(index + 1)")
            }
        }
        XCTAssertTrue(offenders.isEmpty, """
            화면 문구는 Localization.swift 의 `L` 속성으로 옮기고 그걸 참조한다(ko/en/ja 가 모두 받는다): \
            \(offenders.joined(separator: ", "))
            """)
    }

    /// 대조군 — 판정기가 실제로 잡는지와, 주석·문자열 안의 `//` 를 구분하는지.
    func testTheScannerTellsLiteralsFromComments() {
        XCTAssertTrue(Self.hasHangulStringLiteral(#"Text("테스트")"#))
        XCTAssertFalse(Self.hasHangulStringLiteral(#"Text(l.title) // 제목"#))
        XCTAssertTrue(Self.hasHangulStringLiteral(#"Link("https://x", destination: u); Text("안내")"#))
        XCTAssertFalse(Self.hasHangulStringLiteral(#"let s = "a\"b" // 따옴표 뒤 주석"#))
    }

    /// 정규식 대신 글자를 걷는다 — 문자열 안의 `//` 와 진짜 줄 끝 주석을 구분해야 한글 주석(관례)이
    /// 전부 위반으로 읽히지 않는다.
    private static func hasHangulStringLiteral(_ line: String) -> Bool {
        var inString = false
        var escaped = false
        var previous: Character?
        for character in line {
            if escaped { escaped = false; previous = character; continue }
            if character == "\\" && inString { escaped = true; previous = character; continue }
            if character == "\"" { inString.toggle(); previous = character; continue }
            if !inString && character == "/" && previous == "/" { return false }  // 줄 끝 주석
            if inString && isHangul(character) { return true }
            previous = character
        }
        return false
    }

    private static func isHangul(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            (0xAC00...0xD7A3).contains(scalar.value)      // 완성형 음절
                || (0x1100...0x11FF).contains(scalar.value)  // 자모
                || (0x3130...0x318F).contains(scalar.value)  // 호환 자모
        }
    }
}
