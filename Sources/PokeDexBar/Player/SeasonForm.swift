import Foundation

/// 계절 폼 — 사철록·바라철록. 원작 5세대에서 이 둘은 **현실 달력의 달**로 모습이 정해진다.
///
/// **네트워크도 위치 권한도 안 쓴다.** 달은 시계에서 나오고, 반구는 이 기기의 지역에서 나온다
/// (비비용 무늬가 쓰는 것과 같은 `VivillonRegions.current` — 권한이 필요 없는 유일한 위치 신호다).
/// 날씨 폼(캐스퐁·체리꼬)과 달리 바깥에 물어볼 것이 없다.
enum SeasonForm {
    /// 계절 폼이 있는 종. 스프라이트는 봄이 기본이고 나머지 셋만 슬러그를 갖는다.
    static let species: Set<Int> = [585, 586]

    enum Season: String, Codable, Sendable, CaseIterable {
        case spring, summer, autumn, winter

        /// 반대편 반구의 같은 달. 봄↔가을, 여름↔겨울.
        var flipped: Season {
            switch self {
            case .spring: .autumn
            case .autumn: .spring
            case .summer: .winter
            case .winter: .summer
            }
        }
    }

    /// **남반구 지역.** 적도를 걸친 나라는 일부러 북반구로 둔다 — 한 나라를 한쪽으로만 정할 수
    /// 있는데, 잘못 뒤집으면 그 나라 사용자 전부가 반대 계절을 보기 때문이다. 인구가 확실히
    /// 남쪽에 있는 곳만 넣었다(브라질·인도네시아는 주요 도시가 적도 남쪽이라 포함).
    static let southernRegions: Set<String> = [
        "AU", "NZ", "FJ", "PG", "NC", "WS", "TO", "VU", "SB",
        "AR", "BO", "BR", "CL", "PY", "PE", "UY",
        "AO", "BW", "LS", "MG", "MW", "MU", "MZ", "NA", "RE", "SZ", "ZA", "ZM", "ZW",
        "ID", "TL",
    ]

    /// 지금 계절. 반구를 모르면(지역 설정이 없으면) 북반구로 본다.
    static func current(at date: Date,
                        region: String? = VivillonRegions.current,
                        calendar: Calendar = .current) -> Season {
        let northern: Season = switch calendar.component(.month, from: date) {
        case 3, 4, 5: .spring
        case 6, 7, 8: .summer
        case 9, 10, 11: .autumn
        default: .winter
        }
        guard let region, southernRegions.contains(region) else { return northern }
        return northern.flipped
    }

    /// 이 종·이 계절의 Showdown 슬러그. **봄은 nil** — 기본 그림이 봄이라 슬러그가 없다
    /// (메테노처럼 기본 그림이 특수형인 경우와 반대다. `pokedex.json` 으로 확인했다).
    static func slug(speciesID: Int, season: Season?) -> String? {
        guard species.contains(speciesID), let season, season != .spring,
              let base = SpeciesSlug.slug(speciesID) else { return nil }
        return "\(base)-\(season.rawValue)"
    }
}
