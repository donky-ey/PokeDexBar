import Foundation

/// 도감 상세가 보여주는 한 종의 프로필 — PokéAPI 두 엔드포인트(`pokemon-species` + `pokemon`)를
/// 합친 것. 세 언어 문자열을 전부 담아 두므로 언어를 바꿔도 재요청이 없다.
struct SpeciesProfile: Codable, Sendable, Equatable {
    let speciesID: Int
    /// 이름 — ko/en/ja. 이 화면 밖의 이름은 진화라인 캐시(`EvoLine`)에서 오지만, 도감 상세는
    /// 라인을 안 불러도 열리므로 프로필이 직접 든다.
    let nameKo: String
    let nameEn: String
    let nameJa: String
    /// 타입 슬러그("electric") — 표시는 `SpeciesProfile.typeLabel` 이 로컬 표로 옮긴다.
    let typeSlugs: [String]
    /// 키(데시미터) — 본가 단위 그대로 저장하고 표시할 때 m 로 바꾼다.
    let heightDm: Int
    /// 몸무게(헥토그램) — 표시할 때 kg 로.
    let weightHg: Int
    /// 분류("쥐포켓몬") — ko/en/ja.
    let genusKo: String
    let genusEn: String
    let genusJa: String
    /// 도감설명 — ko/en/ja. 최신 버전의 항목을 고른다.
    let flavorKo: String
    let flavorEn: String
    let flavorJa: String

    func name(_ lang: AppLanguage) -> String {
        switch lang { case .ko: nameKo; case .en: nameEn; case .ja: nameJa }
    }

    func typesText(_ lang: AppLanguage) -> String {
        typeSlugs.map { Self.typeLabel($0, lang) }.joined(separator: " · ")
    }

    /// 타입 이름 — 본가 공식 번역 18종. 모르는 슬러그는 그대로 보인다(가리는 것보다 낫다).
    static func typeLabel(_ slug: String, _ lang: AppLanguage) -> String {
        let names: (String, String, String)
        switch slug {
        case "normal":   names = ("노말", "Normal", "ノーマル")
        case "fire":     names = ("불꽃", "Fire", "ほのお")
        case "water":    names = ("물", "Water", "みず")
        case "electric": names = ("전기", "Electric", "でんき")
        case "grass":    names = ("풀", "Grass", "くさ")
        case "ice":      names = ("얼음", "Ice", "こおり")
        case "fighting": names = ("격투", "Fighting", "かくとう")
        case "poison":   names = ("독", "Poison", "どく")
        case "ground":   names = ("땅", "Ground", "じめん")
        case "flying":   names = ("비행", "Flying", "ひこう")
        case "psychic":  names = ("에스퍼", "Psychic", "エスパー")
        case "bug":      names = ("벌레", "Bug", "むし")
        case "rock":     names = ("바위", "Rock", "いわ")
        case "ghost":    names = ("고스트", "Ghost", "ゴースト")
        case "dragon":   names = ("드래곤", "Dragon", "ドラゴン")
        case "dark":     names = ("악", "Dark", "あく")
        case "steel":    names = ("강철", "Steel", "はがね")
        case "fairy":    names = ("페어리", "Fairy", "フェアリー")
        default:         names = (slug, slug, slug)
        }
        switch lang { case .ko: return names.0; case .en: return names.1; case .ja: return names.2 }
    }

    func genus(_ lang: AppLanguage) -> String {
        switch lang { case .ko: genusKo; case .en: genusEn; case .ja: genusJa }
    }

    func flavor(_ lang: AppLanguage) -> String {
        switch lang { case .ko: flavorKo; case .en: flavorEn; case .ja: flavorJa }
    }

    /// 표시용 키 — "0.4 m". 본가처럼 소수 첫째 자리.
    var heightText: String { String(format: "%.1f m", Double(heightDm) / 10) }
    /// 표시용 몸무게 — "6.0 kg".
    var weightText: String { String(format: "%.1f kg", Double(weightHg) / 10) }

    /// 도감설명 원문의 제어문자 정리 — 본가 롬에서 온 텍스트라 `\n`(줄바꿈)·`\u{0C}`(페이지
    /// 넘김)이 박혀 있다. 화면 폭이 다른 이 앱에서는 전부 공백으로 접는 것이 맞다.
    static func cleaned(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\u{0C}", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 언어별 최신 항목 고르기 — flavor_text_entries 는 (언어 × 게임 버전) 격자라 같은 언어가
    /// 여러 번 온다. **마지막 것**을 쓴다: 배열이 버전 순이라 마지막이 최신 게임의 문장이다.
    /// 그 언어가 아예 없으면(마이너 종의 ja 누락 등) 영어로 떨어진다 — 빈 칸보다 낫다.
    static func pick(entries: [(language: String, text: String)], language: String) -> String {
        if let hit = entries.last(where: { $0.language == language }) { return cleaned(hit.text) }
        if let en = entries.last(where: { $0.language == "en" }) { return cleaned(en.text) }
        return ""
    }
}
