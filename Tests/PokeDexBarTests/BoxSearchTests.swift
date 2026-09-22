import XCTest
@testable import PokeDexBar

/// 박스 이름 검색 — 판정은 순수 함수라 직접 물어본다.
final class BoxSearchTests: XCTestCase {

    // MARK: 부분 일치

    func testAPartOfTheNameFinds() {
        XCTAssertTrue(BoxSearch.matches(query: "나옹", name: "나옹", speciesID: 52))
        XCTAssertTrue(BoxSearch.matches(query: "옹", name: "나옹", speciesID: 52))
        XCTAssertFalse(BoxSearch.matches(query: "피카", name: "나옹", speciesID: 52))
    }

    /// **화면에 보이는 그 이름에 맞춘다** — 폼·지방 접두사가 붙은 채로. "갈라르"만 쳐도 그 무리가 다 나온다.
    func testTheFormAndRegionPrefixAreSearchable() {
        XCTAssertTrue(BoxSearch.matches(query: "갈라르", name: "갈라르 나옹", speciesID: 52))
        XCTAssertTrue(BoxSearch.matches(query: "메가", name: "메가 거북왕", speciesID: 9))
    }

    func testEnglishIgnoresCase() {
        XCTAssertTrue(BoxSearch.matches(query: "pika", name: "Pikachu", speciesID: 25))
        XCTAssertTrue(BoxSearch.matches(query: "PIKA", name: "Pikachu", speciesID: 25))
    }

    /// 빈 질의는 아무것도 안 거른다 — 검색을 지우면 박스가 그대로 돌아와야 한다.
    func testAnEmptyQueryPassesEverything() {
        XCTAssertTrue(BoxSearch.matches(query: "", name: "나옹", speciesID: 52))
        XCTAssertTrue(BoxSearch.matches(query: "   ", name: "나옹", speciesID: 52))
    }

    // MARK: 초성

    /// "ㄴㅇ" → 나옹. 한국어 사용자가 당연히 기대하는 동작이다.
    func testInitialConsonantsFind() {
        XCTAssertTrue(BoxSearch.matches(query: "ㄴㅇ", name: "나옹", speciesID: 52))
        XCTAssertTrue(BoxSearch.matches(query: "ㄱㅂㅇ", name: "거북왕", speciesID: 9))
        XCTAssertTrue(BoxSearch.matches(query: "ㅂㅇ", name: "거북왕", speciesID: 9), "가운데부터도 맞아야 한다")
        XCTAssertFalse(BoxSearch.matches(query: "ㄱㅂㅇ", name: "나옹", speciesID: 52))
    }

    func testInitialsAreExtractedFromEverySyllable() {
        XCTAssertEqual(BoxSearch.initials(of: "나옹"), "ㄴㅇ")
        XCTAssertEqual(BoxSearch.initials(of: "거북왕"), "ㄱㅂㅇ")
        XCTAssertEqual(BoxSearch.initials(of: "갈라르 나옹"), "ㄱㄹㄹ ㄴㅇ")
        // 한글이 아닌 글자는 그대로 남는다 — 섞인 이름에서 자리가 밀리지 않게.
        XCTAssertEqual(BoxSearch.initials(of: "Pikachu"), "Pikachu")
    }

    /// **자음만인 질의일 때만** 초성 모드다. 규칙이 예측 가능해야 한다 — 섞인 질의는 일반 매치다.
    func testOnlyAnAllConsonantQueryUsesInitials() {
        XCTAssertTrue(BoxSearch.isInitialQuery("ㄴㅇ"))
        XCTAssertTrue(BoxSearch.isInitialQuery("ㄱ"))
        XCTAssertFalse(BoxSearch.isInitialQuery("나옹"))
        XCTAssertFalse(BoxSearch.isInitialQuery("ㄴ옹"))
        XCTAssertFalse(BoxSearch.isInitialQuery("pika"))
        XCTAssertFalse(BoxSearch.isInitialQuery(""))
    }

    /// 모음 자모는 초성이 아니다 — "ㅏ" 로 초성 검색이 열리면 안 된다.
    func testVowelJamoIsNotAnInitialQuery() {
        XCTAssertFalse(BoxSearch.isInitialQuery("ㅏ"))
        XCTAssertFalse(BoxSearch.isInitialQuery("ㅗㅜ"))
    }

    // MARK: 번호

    func testTheSpeciesNumberFinds() {
        XCTAssertTrue(BoxSearch.matches(query: "25", name: "피카츄", speciesID: 25))
        // 이름을 아직 못 받아 "#25" 로 떠 있는 동안에도 같은 질의가 맞는다.
        XCTAssertTrue(BoxSearch.matches(query: "25", name: "#25", speciesID: 25))
        XCTAssertFalse(BoxSearch.matches(query: "26", name: "피카츄", speciesID: 25))
    }

    // MARK: 위장

    /// **위장한 메타몽이 위장한 종 이름으로 찾히면 정체가 검색창으로 샌다.** 화면이 "???" 를
    /// 보여주는 동안에는 검색도 "???" 로만 걸려야 한다. 이름 판정이 `displayName` 을 그대로
    /// 받으므로 이 성질은 공짜로 따라오지만, 누가 "종 이름으로도 찾게 하자"고 고칠 수 있어 못 박는다.
    func testADisguisedDittoIsNotFoundByTheSpeciesItPretendsToBe() {
        let shown = Individual.unknownName
        XCTAssertFalse(BoxSearch.matches(query: "캐터피", name: shown, speciesID: 10))
        XCTAssertFalse(BoxSearch.matches(query: "ㅋㅌㅍ", name: shown, speciesID: 10))
        XCTAssertTrue(BoxSearch.matches(query: shown, name: shown, speciesID: 10))
    }

    // MARK: 화면 배선

    /// **검색을 바꾸면 담아 둔 선택을 비운다.** 안 그러면 검색으로 가려진 개체가 담긴 채로 남아,
    /// 화면에 보이지도 않는 아이가 일괄 보내기에 딸려 나간다 — 방출은 되돌릴 수 없는 동작이라
    /// "보이는 것이 곧 보낼 것"이 지켜져야 한다.
    ///
    /// `@State` 의 `.onChange` 배선이라 xctest 로 재현이 안 된다 — 소스에서 호출 존재를 본다
    /// (`testTheBackfillIsCalledFromAppLaunchNotOnlyFromAView` 와 같은 방식).
    func testChangingTheQueryClearsTheBulkSelection() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/PokeDexBar/UI/BoxTabView.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        // 주석을 먼저 걷어낸다 — 통짜 검색은 바로 위 주석의 같은 낱말에 걸려, 코드를 지워도 통과한다.
        let code = source.split(separator: "\n")
            .map { $0.contains("//") ? String($0[..<$0.range(of: "//")!.lowerBound]) : String($0) }
            .joined(separator: "\n")
        let onChange = try XCTUnwrap(code.range(of: "onChange(of: query)"))
        let body = String(code[onChange.upperBound...].prefix(200))
        XCTAssertTrue(body.contains("picked = []"), "검색이 바뀌어도 선택이 안 비워진다")
        XCTAssertTrue(body.contains("bulkStep = 0"), "확인 단계가 안 되돌려진다")
    }

    /// 검색은 **보기일 뿐이다** — 저장소를 재배치하는 `sortBox` 와 달리 박스 자체를 안 건드린다.
    func testSearchDoesNotTouchTheStore() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/PokeDexBar/UI/BoxTabView.swift")
        let code = try String(contentsOf: url, encoding: .utf8)
        let visible = try XCTUnwrap(code.range(of: "private var visibleBox"))
        let body = String(code[visible.upperBound...].prefix(400))
        XCTAssertFalse(body.contains("store.mutate"), "검색이 저장소를 고친다")
        XCTAssertFalse(body.contains("sortBox"), "검색이 박스를 재배치한다")
    }

    /// 대조군 — 위장이 아닌 개체는 종 이름으로 정상적으로 찾힌다.
    func testAnUndisguisedPokemonIsFoundNormally() {
        XCTAssertTrue(BoxSearch.matches(query: "캐터피", name: "캐터피", speciesID: 10))
    }
}
