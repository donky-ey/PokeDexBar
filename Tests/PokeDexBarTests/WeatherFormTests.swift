import XCTest
@testable import PokeDexBar

/// 날씨 폼 — 코드 해석·슬러그·응답 파싱·캐시·배선.
@MainActor
final class WeatherFormTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: WMO 코드

    /// 실제 응답이 스스로 단위를 `"wmo code"` 라고 적어 오는 그 표다.
    func testTheWeatherCodesMapToTheFourLooks() {
        for code in [0, 1] {
            XCTAssertEqual(WeatherForm.weather(wmoCode: code, isDay: true), .sunny, "코드 \(code)")
        }
        for code in [51, 53, 55, 61, 63, 65, 80, 81, 82, 95, 96, 99] {
            XCTAssertEqual(WeatherForm.weather(wmoCode: code, isDay: true), .rainy, "코드 \(code)")
        }
        for code in [71, 73, 75, 77, 85, 86] {
            XCTAssertEqual(WeatherForm.weather(wmoCode: code, isDay: true), .snowy, "코드 \(code)")
        }
        // 흐림·안개는 보통 모습이다 — 캐스퐁의 네 번째 모습은 없다.
        for code in [2, 3, 45, 48] {
            XCTAssertEqual(WeatherForm.weather(wmoCode: code, isDay: true), .neutral, "코드 \(code)")
        }
    }

    /// 어는 비·진눈깨비는 눈 쪽 — 얼음이 오는 하늘이면 「눈구름」이 맞다.
    func testFreezingPrecipitationCountsAsSnow() {
        for code in [56, 57, 66, 67] {
            XCTAssertEqual(WeatherForm.weather(wmoCode: code, isDay: true), .snowy, "코드 \(code)")
        }
    }

    /// **밤에는 맑아도 맑음이 아니다**(사용자 지적) — 「기상변화」·「플라워기프트」를 켜는 것은
    /// 쨍한 햇살이지 구름 없는 하늘이 아니다. 새벽 두 시에 체리꼬가 피어 있으면 규칙이 아니라
    /// 버그로 보인다.
    func testAClearNightIsNotSunny() {
        for code in [0, 1] {
            XCTAssertEqual(WeatherForm.weather(wmoCode: code, isDay: false), .neutral, "코드 \(code)")
            XCTAssertEqual(WeatherForm.weather(wmoCode: code, isDay: true), .sunny, "코드 \(code)")
        }
        XCTAssertNil(WeatherForm.slug(speciesID: 421,
                                      weather: WeatherForm.weather(wmoCode: 0, isDay: false)),
                     "밤에 체리꼬가 피었다")
        XCTAssertNil(WeatherForm.slug(speciesID: 351,
                                      weather: WeatherForm.weather(wmoCode: 0, isDay: false)),
                     "밤에 캐스퐁이 해 모습이 됐다")
    }

    /// **비·눈은 밤에도 그대로다** — 비는 해와 무관하게 내린다. 대조군이 없으면 "밤이면 전부
    /// 보통 모습"이라는 잘못된 구현도 위 테스트를 통과한다.
    func testRainAndSnowStillFallAtNight() {
        XCTAssertEqual(WeatherForm.weather(wmoCode: 63, isDay: false), .rainy)
        XCTAssertEqual(WeatherForm.weather(wmoCode: 73, isDay: false), .snowy)
        XCTAssertEqual(WeatherForm.slug(speciesID: 351,
                                        weather: WeatherForm.weather(wmoCode: 63, isDay: false)),
                       "castform-rainy")
    }

    /// 모르는 코드는 보통 모습으로 — 표에 없는 값이 와도 없는 그림을 요청하면 안 된다.
    func testAnUnknownCodeIsNeutral() {
        for code in [-1, 4, 100, 9999] {
            XCTAssertEqual(WeatherForm.weather(wmoCode: code, isDay: true), .neutral, "코드 \(code)")
        }
    }

    // MARK: 슬러그

    func testCastformHasAShapeForEachSky() {
        XCTAssertEqual(WeatherForm.slug(speciesID: 351, weather: .sunny), "castform-sunny")
        XCTAssertEqual(WeatherForm.slug(speciesID: 351, weather: .rainy), "castform-rainy")
        XCTAssertEqual(WeatherForm.slug(speciesID: 351, weather: .snowy), "castform-snowy")
        XCTAssertNil(WeatherForm.slug(speciesID: 351, weather: .neutral), "흐림은 보통 모습이다")
        XCTAssertNil(WeatherForm.slug(speciesID: 351, weather: nil))
    }

    /// **체리꼬는 맑음 하나뿐이다** — 「플라워기프트」가 강한 햇살에만 발동한다.
    func testCherrimOnlyBloomsInTheSun() {
        XCTAssertEqual(WeatherForm.slug(speciesID: 421, weather: .sunny), "cherrim-sunshine")
        for weather in [WeatherForm.Weather.rainy, .snowy, .neutral] {
            XCTAssertNil(WeatherForm.slug(speciesID: 421, weather: weather), "\(weather)")
        }
    }

    func testOtherSpeciesNeverGetAWeatherSlug() {
        for id in [25, 585, 350, 352, 420, 422] {
            XCTAssertNil(WeatherForm.slug(speciesID: id, weather: .sunny), "종 \(id)")
        }
    }

    // MARK: 응답 파싱 — 실제 응답 모양으로

    /// 실제 지오코딩 응답에서 잘라낸 모양이다(키·타입 그대로).
    private let geocoding = Data("""
    {"results":[
      {"id":1,"name":"Seoul","latitude":37.566,"longitude":126.9784,
       "timezone":"Asia/Seoul","country_code":"KR"},
      {"id":2,"name":"Seoul","latitude":40.7,"longitude":-74.0,
       "timezone":"America/New_York","country_code":"US"}
    ],"generationtime_ms":0.69}
    """.utf8)

    /// **동명 도시는 시간대로 가른다.** 첫 결과를 그냥 집으면 다른 대륙의 하늘을 보여 준다 —
    /// 응답이 `timezone` 을 같이 주기에 맞춰 볼 수 있다.
    func testTheCityIsPickedByTimeZoneNotByOrder() throws {
        let seoul = try XCTUnwrap(WeatherClient.coordinate(fromGeocoding: geocoding,
                                                           timezone: "Asia/Seoul"))
        XCTAssertEqual(seoul.latitude, 37.566, accuracy: 0.001)
        XCTAssertEqual(seoul.longitude, 126.9784, accuracy: 0.001)

        let newYork = try XCTUnwrap(WeatherClient.coordinate(fromGeocoding: geocoding,
                                                             timezone: "America/New_York"))
        XCTAssertEqual(newYork.latitude, 40.7, accuracy: 0.001)
    }

    /// 같은 시간대 후보가 없으면 **아무 도시나 집지 않는다** — 엉뚱한 날씨보다 없는 게 낫다.
    func testNoMatchingTimeZoneMeansNoCoordinate() {
        XCTAssertNil(WeatherClient.coordinate(fromGeocoding: geocoding, timezone: "Europe/Paris"))
    }

    /// 결과가 없을 때 실제 응답은 `results` 키 자체가 없다(실측).
    func testAnEmptyGeocodingResponseIsHandled() {
        let empty = Data(#"{"generationtime_ms":0.127}"#.utf8)
        XCTAssertNil(WeatherClient.coordinate(fromGeocoding: empty, timezone: "Asia/Seoul"))
        XCTAssertNil(WeatherClient.coordinate(fromGeocoding: Data("not json".utf8),
                                              timezone: "Asia/Seoul"))
    }

    func testTheForecastCodeAndDaylightAreRead() throws {
        let forecast = Data("""
        {"latitude":37.55,"longitude":127.0,
         "current_units":{"time":"iso8601","weather_code":"wmo code","is_day":""},
         "current":{"time":"2026-09-03T08:45","interval":900,"weather_code":61,"is_day":0}}
        """.utf8)
        let sky = try XCTUnwrap(WeatherClient.sky(fromForecast: forecast))
        XCTAssertEqual(sky.code, 61)
        XCTAssertFalse(sky.isDay, "is_day 0 은 밤이다")
        XCTAssertNil(WeatherClient.sky(fromForecast: Data(#"{"current":{}}"#.utf8)))
        XCTAssertNil(WeatherClient.sky(fromForecast: Data("not json".utf8)))
    }

    /// `is_day` 가 빠진 응답은 **낮으로 본다** — 밤으로 단정하면 맑은 날의 캐스퐁이 통째로
    /// 사라진다. 모를 때는 지금까지 하던 대로가 낫다.
    func testAMissingDaylightFieldIsTreatedAsDay() throws {
        let forecast = Data(#"{"current":{"weather_code":0}}"#.utf8)
        let sky = try XCTUnwrap(WeatherClient.sky(fromForecast: forecast))
        XCTAssertTrue(sky.isDay)
        XCTAssertEqual(WeatherForm.weather(wmoCode: sky.code, isDay: sky.isDay), .sunny)
    }

    /// **낮/밤을 실제로 물어보는가.** 파서는 `is_day` 가 없으면 낮으로 넘어가므로, 요청에서
    /// 이 필드가 빠지면 밤에 체리꼬가 피는 결함으로 조용히 돌아간다(뮤테이션에서 그 되돌림이
    /// 아무 테스트도 안 깼다). 값 해석이 아니라 **무엇을 물어보는지**를 잠근다.
    func testTheForecastAsksForDaylight() throws {
        let url = try XCTUnwrap(WeatherClient.forecastURL(latitude: 37.566, longitude: 126.9784))
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let current = try XCTUnwrap(items.first { $0.name == "current" }?.value)
        XCTAssertTrue(current.contains("is_day"), "낮/밤을 안 물어본다: \(current)")
        XCTAssertTrue(current.contains("weather_code"), "날씨를 안 물어본다: \(current)")
        XCTAssertEqual(items.first { $0.name == "latitude" }?.value, "37.566")
    }

    // MARK: 시간대 → 도시

    func testTheCityComesFromTheTimeZone() {
        XCTAssertEqual(WeatherClient.cityName(forTimeZone: "Asia/Seoul"), "Seoul")
        XCTAssertEqual(WeatherClient.cityName(forTimeZone: "America/New_York"), "New York")
        XCTAssertEqual(WeatherClient.cityName(forTimeZone: "America/Argentina/Buenos_Aires"),
                       "Buenos Aires", "세 조각짜리 시간대도 마지막이 도시다")
    }

    /// 도시가 없는 시간대로는 하늘을 물어볼 데가 없다 — 물어보지 않는다.
    func testTimeZonesWithoutACityAskNothing() {
        for identifier in ["UTC", "GMT", "Etc/GMT+9", "Etc/UTC", ""] {
            XCTAssertNil(WeatherClient.cityName(forTimeZone: identifier), identifier)
        }
    }

    // MARK: 캐시

    func testTheCacheGoesStaleAfterAnHour() {
        let cache = WeatherClient.Cache(timezone: "Asia/Seoul", latitude: 0, longitude: 0,
                                        code: 0, isDay: true, fetchedAt: now)
        XCTAssertTrue(cache.isFresh(at: now))
        XCTAssertTrue(cache.isFresh(at: now.addingTimeInterval(WeatherClient.ttl - 1)))
        XCTAssertFalse(cache.isFresh(at: now.addingTimeInterval(WeatherClient.ttl)))
        XCTAssertFalse(cache.isFresh(at: now.addingTimeInterval(-1)), "시계가 뒤로 가면 다시 묻는다")
    }

    // MARK: 개체 배선

    private func individual(_ speciesID: Int, weather: WeatherForm.Weather?) -> Individual {
        var one = Individual(baseID: speciesID, speciesID: speciesID, pathIDs: [speciesID],
                             nature: .hardy, obtainedAt: now, grade: .common)
        one.weather = weather
        return one
    }

    func testTheSpriteFollowsTheSky() {
        XCTAssertEqual(individual(351, weather: .rainy).spriteForm, "castform-rainy")
        XCTAssertNil(individual(351, weather: .neutral).spriteForm)
        XCTAssertEqual(individual(421, weather: .sunny).spriteForm, "cherrim-sunshine")
    }

    /// **아는 날씨가 확률을 이긴다.** 비 오는 날에 20% 로 꽃이 피면, 방금 받아 온 하늘을
    /// 스스로 뒤집는 셈이다. `nil`(모름)과 `.rainy`(안다) 를 가르는 것이 이 분기의 요점이다.
    func testAKnownSkyOverridesTheBloomRoll() throws {
        // 굴림이 실제로 피우는 개체를 찾는다 — 못 찾으면 이 테스트는 아무것도 안 지킨다.
        // 개화는 **곁에 둘 때만** 굴린다(`BattleStateForm.cherrimSlug`).
        var blooming: Individual?
        for _ in 0..<500 {
            var candidate = individual(421, weather: nil)
            candidate.partnerSince = now
            if candidate.spriteForm == "cherrim-sunshine" { blooming = candidate; break }
        }
        var bloomer = try XCTUnwrap(blooming, "확률 개화 개체를 못 만들었다 — 테스트가 무의미해진다")

        bloomer.weather = .rainy
        XCTAssertNil(bloomer.spriteForm, "비가 오는데 확률 개화가 하늘을 이겼다")
        bloomer.weather = .sunny
        XCTAssertEqual(bloomer.spriteForm, "cherrim-sunshine")
    }

    func testAWeatherOnTheWrongSpeciesIsDropped() {
        XCTAssertNil(individual(25, weather: .sunny).sanitized().weather)
        XCTAssertEqual(individual(351, weather: .sunny).sanitized().weather, .sunny)
    }

    // MARK: 스토어

    private func makeStore() -> PlayerStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("weather-\(UUID().uuidString).json")
        return PlayerStore(fileURL: url, rng: SeededRNG(seed: 6), now: { self.now })
    }

    /// **날씨를 타는 아이가 없으면 아예 안 묻는다** — 대부분의 사용자에게 요청이 0 이 된다.
    func testNobodyToDressMeansNoRequest() {
        let store = makeStore()
        XCTAssertFalse(store.needsWeather, "빈 박스인데 날씨를 물으려 한다")
        store.addForTesting(individual(25, weather: nil))
        XCTAssertFalse(store.needsWeather, "피카츄 때문에 날씨를 물으려 한다")
        store.addForTesting(individual(351, weather: nil))
        XCTAssertTrue(store.needsWeather)
    }

    func testApplyingWeatherOnlyTouchesTheSpeciesThatCare() {
        let store = makeStore()
        store.addForTesting(individual(25, weather: nil))
        store.addForTesting(individual(351, weather: nil))
        store.addForTesting(individual(421, weather: nil))
        store.applyWeather(.snowy)

        XCTAssertNil(store.state.box.first { $0.speciesID == 25 }?.weather)
        XCTAssertEqual(store.state.box.first { $0.speciesID == 351 }?.weather, .snowy)
        XCTAssertEqual(store.state.box.first { $0.speciesID == 421 }?.weather, .snowy)
    }

    /// 날씨는 **기동 틱**에서 온다 — 뷰에 매달면 그 화면을 안 여는 사람에게는 영영 안 돈다.
    func testTheFetchIsWiredIntoTheTick() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/PokeDexBar/PokeDexBarApp.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        let code = source.split(separator: "\n")
            .map { $0.contains("//") ? String($0[..<$0.range(of: "//")!.lowerBound]) : String($0) }
            .joined(separator: "\n")
        XCTAssertTrue(code.contains("applyWeather("), "틱이 날씨를 개체에 안 적는다")
        XCTAssertTrue(code.contains("needsWeather"), "날씨를 타는 아이가 없어도 요청이 나간다")
    }
}
