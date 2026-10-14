import XCTest
@testable import PokeDexBar

/// 조건·결과가 갈리는 간선을 카탈로그가 **다 덮는지.** 데이터가 늘면(새 세대) 여기서 알려 준다.
/// 지금은 각각 2건이고, **0이 아닌 것을 확인했다** — 한 번도 안 걸리는 가드는 장식이다.
///
/// 간선 목록은 `scripts/generate-evolution-form-edges.py` 가 PokéAPI 540체인에서 뽑는다. 세는 기준은
/// "필드가 있다"가 아니라 "앱이 읽는 필드에서 조건이 폼마다 갈린다"다 — 존재로 세면 47건이 나오는데
/// 대부분 같은 조건을 폼 수만큼 되풀이할 뿐이다(스크립트 독스트링).
final class EvolutionFormCoverageTests: XCTestCase {
    private struct Edge: Decodable { let from: Int; let to: Int }
    private struct Fixture: Decodable { let itemDecides: [Edge]; let formDecides: [Edge] }

    private func fixture() throws -> Fixture {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "form-split-edges", withExtension: "json",
                              subdirectory: "EvolutionForms"),
            "픽스처가 없다 — Package.swift 의 resources 에 Fixtures/EvolutionForms 가 있는지 보라")
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    func testEveryItemDecidedEdgeIsCatalogued() throws {
        for edge in try fixture().itemDecides {
            XCTAssertFalse(EvolvedFormCatalog.all.filter { $0.speciesID == edge.to }.isEmpty,
                           "#\(edge.from)→#\(edge.to) 를 EvolvedFormCatalog 가 모른다")
        }
    }

    func testEveryFormDecidedEdgeHasBirthForms() throws {
        for edge in try fixture().formDecides {
            XCTAssertFalse(BirthFormCatalog.forms(speciesID: edge.from).isEmpty,
                           "#\(edge.from) 의 태생 모습이 없다 — 조건을 가를 축이 없다")
        }
    }

    func testTheSweepFoundSomething() throws {
        XCTAssertFalse(try fixture().itemDecides.isEmpty)
        XCTAssertFalse(try fixture().formDecides.isEmpty)
    }
}
