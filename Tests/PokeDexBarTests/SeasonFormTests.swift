import XCTest
@testable import PokeDexBar

/// 계절 폼 — 달력·반구·슬러그·배선.
@MainActor
final class SeasonFormTests: XCTestCase {
    /// 테스트가 이 기기의 시간대에 안 흔들리게 UTC 로 고정한다.
    private var utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func date(month: Int) -> Date {
        utc.date(from: DateComponents(year: 2026, month: month, day: 15))!
    }

    // MARK: 달력

    func testTheNorthernMonthsMapToTheirSeasons() {
        let expected: [Int: SeasonForm.Season] = [
            1: .winter, 2: .winter, 3: .spring, 4: .spring, 5: .spring, 6: .summer,
            7: .summer, 8: .summer, 9: .autumn, 10: .autumn, 11: .autumn, 12: .winter,
        ]
        for (month, season) in expected {
            XCTAssertEqual(SeasonForm.current(at: date(month: month), region: "KR", calendar: utc),
                           season, "\(month)월")
        }
    }

    /// 남반구는 정확히 반대편이다 — 호주의 12월은 여름이다.
    func testTheSouthernHemisphereIsFlipped() {
        for month in 1...12 {
            let north = SeasonForm.current(at: date(month: month), region: "KR", calendar: utc)
            let south = SeasonForm.current(at: date(month: month), region: "AU", calendar: utc)
            XCTAssertEqual(south, north.flipped, "\(month)월")
        }
        XCTAssertEqual(SeasonForm.current(at: date(month: 12), region: "AU", calendar: utc), .summer)
        XCTAssertEqual(SeasonForm.current(at: date(month: 12), region: "KR", calendar: utc), .winter)
    }

    /// 지역을 모르면 북반구로 본다 — 뒤집을 근거가 없으면 뒤집지 않는다.
    func testAnUnknownRegionStaysNorthern() {
        XCTAssertEqual(SeasonForm.current(at: date(month: 12), region: nil, calendar: utc), .winter)
        XCTAssertEqual(SeasonForm.current(at: date(month: 12), region: "ZZ", calendar: utc), .winter)
    }

    /// 뒤집기가 두 번이면 제자리 — 계절이 넷이고 반년 차이라는 성질 자체를 잠근다.
    func testFlippingTwiceComesBack() {
        for season in SeasonForm.Season.allCases {
            XCTAssertEqual(season.flipped.flipped, season)
            XCTAssertNotEqual(season.flipped, season)
        }
    }

    // MARK: 슬러그

    /// **봄은 슬러그가 없다** — 기본 그림이 봄이다. nil 이 곧 "종 번호 기본 그림"이다.
    func testSpringIsTheBaseSprite() {
        XCTAssertNil(SeasonForm.slug(speciesID: 585, season: .spring))
        XCTAssertNil(SeasonForm.slug(speciesID: 585, season: nil))
    }

    func testTheOtherSeasonsHaveTheirOwnSprite() {
        XCTAssertEqual(SeasonForm.slug(speciesID: 585, season: .summer), "deerling-summer")
        XCTAssertEqual(SeasonForm.slug(speciesID: 585, season: .autumn), "deerling-autumn")
        XCTAssertEqual(SeasonForm.slug(speciesID: 585, season: .winter), "deerling-winter")
        XCTAssertEqual(SeasonForm.slug(speciesID: 586, season: .winter), "sawsbuck-winter")
    }

    /// 계절 폼이 없는 종에는 슬러그가 안 붙는다 — 붙으면 없는 그림을 요청한다.
    func testOtherSpeciesNeverGetASeasonSlug() {
        for id in [25, 421, 351, 584, 587] {
            XCTAssertNil(SeasonForm.slug(speciesID: id, season: .winter), "종 \(id)")
        }
    }

    /// 슬러그가 그 종의 것인지 — `SpeciesSlug` 표에서 유도했는지 확인한다(하드코딩하면 오타가
    /// 조용히 남는다). 파밀리쥐에서 실제로 방향을 틀린 전례가 있다.
    func testEverySlugBelongsToItsSpecies() {
        for id in SeasonForm.species {
            let base = SpeciesSlug.slug(id)
            XCTAssertNotNil(base, "종 \(id) 의 기본 슬러그가 없다")
            for season in SeasonForm.Season.allCases where season != .spring {
                XCTAssertEqual(SeasonForm.slug(speciesID: id, season: season), "\(base!)-\(season.rawValue)")
            }
        }
    }

    // MARK: 개체 배선

    private func deerling(season: SeasonForm.Season?) -> Individual {
        var individual = Individual(baseID: 585, speciesID: 585, pathIDs: [585], nature: .hardy,
                                    obtainedAt: Date(timeIntervalSince1970: 0), grade: .common)
        individual.season = season
        return individual
    }

    func testTheSpriteFollowsTheSeason() {
        XCTAssertEqual(deerling(season: .winter).spriteForm, "deerling-winter")
        XCTAssertNil(deerling(season: .spring).spriteForm, "봄은 기본 그림이라 슬러그가 없다")
        XCTAssertNil(deerling(season: nil).spriteForm)
    }

    /// **도감은 계절로 안 나뉜다.** 계절은 개체가 가진 성질이 아니라 지나가는 상태라, 태생
    /// 무늬·지방처럼 도감을 쪼개면 한 마리를 사계절 내내 다시 등록하게 된다.
    func testSeasonsDoNotSplitTheDex() {
        let keys = SeasonForm.Season.allCases.map { DexKey.key(for: deerling(season: $0)) }
        XCTAssertEqual(Set(keys), ["585"], "계절이 도감 키를 갈랐다: \(keys)")
    }

    /// 계절 폼이 없는 종에 계절이 적힌 세이브는 경계에서 걸러진다(관대 디코딩의 짝).
    func testASeasonOnTheWrongSpeciesIsDropped() {
        var pikachu = Individual(baseID: 25, speciesID: 25, pathIDs: [25], nature: .hardy,
                                 obtainedAt: Date(timeIntervalSince1970: 0), grade: .common)
        pikachu.season = .winter
        XCTAssertNil(pikachu.sanitized().season)
        XCTAssertEqual(deerling(season: .winter).sanitized().season, .winter, "정상 종은 그대로")
    }

    // MARK: 갱신

    private func makeStore(now: @escaping () -> Date) -> PlayerStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("season-\(UUID().uuidString).json")
        return PlayerStore(fileURL: url, rng: SeededRNG(seed: 4), now: now)
    }

    func testTheTickWritesTheCurrentSeason() {
        let store = makeStore(now: { Date() })
        store.addForTesting(deerling(season: nil))
        store.refreshSeasons()
        XCTAssertEqual(store.state.box.first?.season, SeasonForm.current(at: Date()),
                       "틱이 계절을 안 적었다")
    }

    /// 계절 폼이 없는 종은 건드리지 않는다 — 대조군. 없으면 "전부에 적는다"도 통과한다.
    func testTheTickLeavesOtherSpeciesAlone() {
        let store = makeStore(now: { Date() })
        store.addForTesting(Individual(baseID: 25, speciesID: 25, pathIDs: [25], nature: .hardy,
                                       obtainedAt: Date(timeIntervalSince1970: 0), grade: .common))
        store.refreshSeasons()
        XCTAssertNil(store.state.box.first?.season)
    }

    /// 계절은 **기동 경로**에서 맞춰진다 — `update` 안에 두면 토큰을 안 쓴 날엔 안 돈다.
    /// 뷰에 매달린 보정이 영영 안 돌던 전례(성별)와 같은 부류라, 호출 존재를 소스로 확인한다.
    func testTheRefreshIsCalledFromTheTickNotOnlyFromAView() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/PokeDexBar/PokeDexBarApp.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        // 주석을 먼저 걷어낸다 — 통짜 검색은 바로 위 주석의 같은 낱말에 걸려, 호출을 지워도
        // 통과한다(성별 보정 가드에서 실제로 그렇게 새어 나갔다).
        let code = source.split(separator: "\n")
            .map { $0.contains("//") ? String($0[..<$0.range(of: "//")!.lowerBound]) : String($0) }
            .joined(separator: "\n")
        XCTAssertTrue(code.contains("refreshSeasons()"), "기동 틱에서 계절을 안 맞춘다")
    }
}
