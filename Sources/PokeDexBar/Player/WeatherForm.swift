import Foundation

/// 날씨 폼 — 캐스퐁·체리꼬. 계절(`SeasonForm`)과 달리 **바깥에 물어봐야 답이 나오는** 유일한
/// 폼이라, 이 파일은 판정만 갖고 받아오는 일은 `WeatherClient` 가 한다.
///
/// **모르면 아무 일도 안 일어난다.** 네트워크가 없거나 지역을 못 찾으면 캐스퐁은 보통 모습이고
/// 체리꼬는 예전처럼 확률로 핀다 — 날씨는 얹는 층이지 의존이 아니다.
enum WeatherForm {
    static let species: Set<Int> = [351, 421]

    enum Weather: String, Codable, Sendable, CaseIterable {
        case sunny, rainy, snowy, neutral
    }

    /// WMO 코드 → 날씨. 값은 Open-Meteo 응답의 `weather_code` 이고, 그 응답이 스스로 단위를
    /// `"wmo code"` 라고 적어 온다(실제 응답으로 확인).
    ///
    /// **어는 비·진눈깨비(56·57·66·67)는 눈 쪽이다** — 캐스퐁의 세 번째 모습은 「눈구름」이고
    /// 원작에서도 싸라기눈(우박) 날씨에 나온다. 얼음이 오는 하늘이면 그쪽이 맞다.
    ///
    /// **밤에는 맑아도 맑음이 아니다**(사용자 지적). 캐스퐁의 「기상변화」와 체리꼬의
    /// 「플라워기프트」를 켜는 것은 *쨍한 햇살*이지 구름 없는 하늘이 아니다 — 새벽 두 시에
    /// 체리꼬가 활짝 피어 있으면 규칙이 아니라 버그로 보인다. 비·눈은 밤에도 그대로다:
    /// 비는 해와 무관하게 내린다. 낮/밤은 응답의 `is_day` 가 알려 준다(1=낮).
    static func weather(wmoCode: Int, isDay: Bool) -> Weather {
        switch wmoCode {
        case 0, 1: isDay ? .sunny : .neutral                     // 맑음·대체로 맑음 — 해가 떠 있을 때만
        case 56, 57, 66, 67, 71, 73, 75, 77, 85, 86: .snowy      // 어는 비·눈·눈소나기
        case 51, 53, 55, 61, 63, 65, 80, 81, 82, 95, 96, 99: .rainy  // 이슬비·비·소나기·뇌우
        default: .neutral                                        // 흐림(2·3)·안개(45·48)
        }
    }

    /// 이 종·이 날씨의 Showdown 슬러그. 해당 모습이 없으면 nil → 기본 그림.
    ///
    /// **체리꼬는 맑음 하나뿐이다** — 원작의 「플라워기프트」가 강한 햇살에만 발동한다.
    /// 비·눈에는 접힌 모습 그대로다.
    static func slug(speciesID: Int, weather: Weather?) -> String? {
        guard let weather, weather != .neutral else { return nil }
        switch speciesID {
        case 351: return "castform-\(weather.rawValue)"
        case 421: return weather == .sunny ? "cherrim-sunshine" : nil
        default: return nil
        }
    }
}
