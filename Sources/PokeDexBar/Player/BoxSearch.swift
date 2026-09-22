import Foundation

/// 박스 이름 검색의 판정. **순수 함수라 테스트가 직접 물어본다** — 뷰 안에 묻어 두면
/// "초성이 맞는가"·"위장이 새지 않는가"를 물어볼 수가 없다.
///
/// 검색은 **보기일 뿐이다.** 정리(`PlayerStore.sortBox`)는 저장소를 실제로 재배치하는 명령이지만
/// 검색은 보고 있는 동안만 거른다 — 그래서 여기에는 상태가 없다.
enum BoxSearch {
    /// 한글 초성 19자. 순서가 곧 초성 인덱스다(유니코드 한글 음절의 정의).
    private static let choseong = Array("ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ")
    private static let syllableBase: UInt32 = 0xAC00
    private static let syllableEnd: UInt32 = 0xD7A3
    /// 한 초성이 담당하는 음절 수 — 중성 21 × 종성 28.
    private static let syllablesPerChoseong: UInt32 = 588

    /// 이 개체가 질의에 걸리나.
    ///
    /// - Parameter name: **화면에 보이는 그 이름**(`Individual.displayName`). 종 이름이 아니라
    ///   폼·지방 접두사가 붙은 표시 이름이라, "갈라르"만 쳐도 그 무리가 걸린다. 위장 중인
    ///   메타몽은 이 값이 "???" 라 **위장한 종 이름으로는 안 걸린다** — 걸리면 정체가 검색창으로 샌다.
    static func matches(query: String, name: String, speciesID: Int) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return true }
        if isInitialQuery(trimmed) {
            return initials(of: name).contains(trimmed)
        }
        if contains(name, trimmed) { return true }
        // 번호로도 찾는다 — 이름을 아직 못 받아 "#25" 로 떠 있는 동안에도, 받은 뒤에도 같은
        // 질의가 통하도록. (이름이 "#25" 일 때는 위 이름 매치로도 걸리지만, 받은 뒤에는 여기뿐이다.)
        return String(speciesID).contains(trimmed)
    }

    /// 질의가 **전부 초성 자모**인가. 그럴 때만 초성 모드로 간다 — 섞인 질의("ㄴ옹")까지 받으면
    /// 규칙이 예측 불가능해지고, 실제로 그렇게 치는 사람도 없다.
    ///
    /// 모음 자모(ㅏ·ㅗ)는 초성이 아니다. `choseong` 에 없으므로 자동으로 걸러진다.
    static func isInitialQuery(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        return trimmed.allSatisfy { choseong.contains($0) }
    }

    /// 한글 음절을 초성으로 바꾼 문자열. **한글이 아닌 글자는 그대로 남긴다** — 지우면 섞인
    /// 이름("갈라르 나옹")에서 자리가 밀려 엉뚱한 곳이 맞는다.
    static func initials(of text: String) -> String {
        String(text.map { character -> Character in
            guard let scalar = character.unicodeScalars.first,
                  character.unicodeScalars.count == 1,
                  scalar.value >= syllableBase, scalar.value <= syllableEnd else { return character }
            let index = Int((scalar.value - syllableBase) / syllablesPerChoseong)
            return choseong[index]
        })
    }

    /// 대소문자·발음기호를 무시한 부분 일치. 영어 이름(Pikachu/PIKA)과 프랑스어계 이름
    /// (Flabébé)을 같이 받아 준다.
    private static func contains(_ haystack: String, _ needle: String) -> Bool {
        haystack.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}
