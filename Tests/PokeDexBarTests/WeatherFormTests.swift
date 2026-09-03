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
            XCTAssertEqual(WeatherForm.weather(wmoCode: code), .sunny, "코드 \(code)")
        }
        for code in [51, 53, 55, 61, 63, 65, 80, 81, 82, 95, 96, 99] {
            XCTAssertEqual(WeatherForm.weather(wmoCode: code), .rainy, "코드 \(code)")
        }
        for code in [71, 73, 75, 77, 85, 86] {
            XCTAssertEqual(WeatherForm.weather(wmoCode: code), .snowy, "코드 \(code)")
        }
        // 흐림·안개는 보통 모습이다 — 캐스퐁의 네 번째 모습은 없다.
        for code in [2, 3, 45, 48] {
            XCTAssertEqual(WeatherForm.weather(wmoCode: code), .neutral, "코드 \(code)")
        }
    }

    /// 어는 비·진눈깨비는 눈 쪽 — 얼음이 오는 하늘이면 「눈구름」이 맞다.
    func testFreezingPrecipitationCountsAsSnow() {
        for code in [56, 57, 66, 67] {
            XCTAssertEqual(WeatherForm.weather(wmoCode: code), .snowy, "코드 \(code)")
        }
    }

    /// 모르는 코드는 보통 모습으로 — 표에 없는 값이 와도 없는 그림을 요청하면 안 된다.
    func testAnUnknownCodeIsNeutral() {
        for code in [-1, 4, 100, 9999] {
            XCTAssertEqual(WeatherForm.weather(wmoCode: code), .neutral, "코드 \(code)")
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

    func testTheForecastCodeIsRead() {
        let forecast = Data("""
        {"latitude":37.55,"longitude":127.0,
         "current_units":{"time":"iso8601","weather_code":"wmo code"},
         "current":{"time":"2026-09-03T08:30","interval":900,"weather_code":61}}
        """.utf8)
        XCTAssertEqual(WeatherClient.code(fromForecast: forecast), 61)
        XCTAssertNil(WeatherClient.code(fromForecast: Data(#"{"current":{}}"#.utf8)))
        XCTAssertNil(WeatherClient.code(fromForecast: Data("not json".utf8)))
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
                                        code: 0, fetchedAt: now)
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
