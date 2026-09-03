import Foundation

/// 지금 날씨를 받아 오는 곳. 캐스퐁·체리꼬의 모습이 여기서 나온다(`WeatherForm`).
///
/// **위치 권한을 안 받는다.** 좌표는 시스템 시간대(`Asia/Seoul`)의 마지막 조각을 도시 이름으로
/// 읽어 지오코딩해서 얻는다 — CoreLocation 을 쓰면 TCC 프롬프트가 뜨고, 자체 서명 앱은 재서명
/// 때마다 그 승인이 풀린다(CLAUDE.md 의 키체인 ACL 과 같은 부류). 시간대는 사용자가 이미
/// 스스로 정해 둔 값이고, 도시 단위면 하늘이 맑은지 아닌지에는 충분하다.
///
/// **보내는 좌표는 사용자의 실제 위치가 아니다** — 시간대가 대표하는 도시의 좌표다. 비비용
/// 무늬가 국가를 쓰는 것과 같은 급의 신호이고, 오히려 그보다 정밀하지 않다.
actor WeatherClient {
    static let shared = WeatherClient()

    /// 한 번 받아 오면 이만큼은 다시 안 묻는다. 하늘은 2분마다 바뀌지 않고, 사용량 틱이
    /// 그 간격으로 돌기 때문에 이 문턱이 없으면 하루 700번을 부른다.
    static let ttl: TimeInterval = 3600

    private let fileURL: URL
    private var cache: Cache?

    init(fileURL: URL = AppEnv.supportDirectory().appendingPathComponent("weather.json")) {
        self.fileURL = fileURL
        cache = (try? Data(contentsOf: fileURL)).flatMap { try? JSONDecoder().decode(Cache.self, from: $0) }
    }

    /// 좌표는 시간대가 안 바뀌면 영원히 같다 — 날씨와 같은 파일에 두되 따로 만료시킨다.
    struct Cache: Codable, Sendable {
        var timezone: String
        var latitude: Double
        var longitude: Double
        var code: Int
        var fetchedAt: Date

        func isFresh(at now: Date, ttl: TimeInterval = WeatherClient.ttl) -> Bool {
            let age = now.timeIntervalSince(fetchedAt)
            return age >= 0 && age < ttl
        }
    }

    /// 지금 날씨. 못 받아 오면 **오래된 값이라도** 돌려준다 — 어제의 하늘이 아무것도 없는 것보다
    /// 낫고, 실패했다고 캐스퐁이 갑자기 보통 모습으로 돌아가면 그게 더 이상하다.
    func current(now: Date = Date(),
                 timezone: String = TimeZone.current.identifier) async -> WeatherForm.Weather? {
        if let cache, cache.timezone == timezone, cache.isFresh(at: now) {
            return WeatherForm.weather(wmoCode: cache.code)
        }
        // 시간대가 그대로면 좌표를 다시 찾지 않는다.
        var coordinate: (latitude: Double, longitude: Double)?
        if let cache, cache.timezone == timezone {
            coordinate = (cache.latitude, cache.longitude)
        } else {
            coordinate = await geocode(timezone: timezone)
        }
        guard let coordinate else { return staleWeather() }
        guard let code = await forecast(latitude: coordinate.latitude,
                                        longitude: coordinate.longitude) else {
            return staleWeather()
        }
        let fresh = Cache(timezone: timezone, latitude: coordinate.latitude,
                          longitude: coordinate.longitude, code: code, fetchedAt: now)
        cache = fresh
        try? JSONEncoder().encode(fresh).write(to: fileURL, options: .atomic)
        return WeatherForm.weather(wmoCode: code)
    }

    private func staleWeather() -> WeatherForm.Weather? {
        cache.map { WeatherForm.weather(wmoCode: $0.code) }
    }

    // MARK: 순수 부분 — 네트워크 없이 테스트한다

    /// 시간대에서 도시 이름을 꺼낸다. `Asia/Seoul` → `Seoul`, `America/New_York` → `New York`.
    /// **도시가 아닌 시간대는 nil** — `UTC`·`Etc/GMT+9` 로는 하늘을 물어볼 데가 없다.
    nonisolated static func cityName(forTimeZone identifier: String) -> String? {
        let parts = identifier.split(separator: "/")
        guard parts.count >= 2, parts[0] != "Etc" else { return nil }
        let city = parts.last!.replacingOccurrences(of: "_", with: " ")
        return city.isEmpty ? nil : city
    }

    /// 지오코딩 응답에서 **우리 시간대와 같은** 후보의 좌표를 고른다.
    ///
    /// 이름만 보고 첫 결과를 집으면 동명 도시에 걸린다(응답이 `timezone` 을 같이 주기에 맞춰
    /// 볼 수 있다 — 실제 응답으로 확인). 같은 시간대 후보가 없으면 nil 이지, 아무 도시나
    /// 집지 않는다 — 엉뚱한 대륙의 날씨를 보여 주느니 안 보여 주는 게 낫다.
    nonisolated static func coordinate(fromGeocoding data: Data,
                                       timezone: String) -> (latitude: Double, longitude: Double)? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = root["results"] as? [[String: Any]] else { return nil }
        for result in results where result["timezone"] as? String == timezone {
            guard let lat = result["latitude"] as? Double,
                  let lon = result["longitude"] as? Double else { continue }
            return (lat, lon)
        }
        return nil
    }

    /// 예보 응답에서 WMO 코드를 꺼낸다.
    nonisolated static func code(fromForecast data: Data) -> Int? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let current = root["current"] as? [String: Any] else { return nil }
        return current["weather_code"] as? Int
    }

    // MARK: 네트워크

    private func geocode(timezone: String) async -> (latitude: Double, longitude: Double)? {
        guard let city = Self.cityName(forTimeZone: timezone),
              var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")
        else { return nil }
        components.queryItems = [
            .init(name: "name", value: city),
            .init(name: "count", value: "10"),   // 동명 도시가 있어 시간대로 골라야 한다
            .init(name: "format", value: "json"),
        ]
        guard let url = components.url,
              let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return Self.coordinate(fromGeocoding: data, timezone: timezone)
    }

    private func forecast(latitude: Double, longitude: Double) async -> Int? {
        guard var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        else { return nil }
        components.queryItems = [
            .init(name: "latitude", value: String(latitude)),
            .init(name: "longitude", value: String(longitude)),
            .init(name: "current", value: "weather_code"),
        ]
        guard let url = components.url,
              let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return Self.code(fromForecast: data)
    }
}
