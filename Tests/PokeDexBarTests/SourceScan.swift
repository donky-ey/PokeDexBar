/// 소스를 훑는 가드들이 함께 쓰는 줄 단위 워커.
///
/// 정규식이나 `range(of: "//")` 로 주석을 자르면 문자열 안의 `//`(`"https://…"`)에서도 잘려, 그 뒤의 코드가
/// 가드에서 빠진다. 글자를 걸으며 문자열 안팎을 구분해 한 곳에서 처리한다.
enum SourceScan {
    /// 줄 끝 `//` 주석을 걷어낸 코드 부분.
    static func code(_ line: String) -> String { walk(line).code }

    /// 주석 앞 코드에 있는 문자열 리터럴들의 내용(따옴표 제외).
    static func stringLiterals(_ line: String) -> [String] { walk(line).literals }

    private static func walk(_ line: String) -> (code: String, literals: [String]) {
        var code = ""
        var literals: [String] = []
        var current = ""
        var inString = false
        var escaped = false
        var previous: Character?
        for character in line {
            if inString {
                code.append(character)
                if escaped {
                    escaped = false
                    current.append(character)
                } else if character == "\\" {
                    escaped = true
                    current.append(character)
                } else if character == "\"" {
                    inString = false
                    literals.append(current)
                    current = ""
                } else {
                    current.append(character)
                }
                previous = character
                continue
            }
            if character == "/" && previous == "/" {   // 줄 끝 주석 — 앞의 "/" 까지 걷어낸다
                code.removeLast()
                return (code, literals)
            }
            if character == "\"" { inString = true }
            code.append(character)
            previous = character
        }
        if inString { literals.append(current) }
        return (code, literals)
    }
}
