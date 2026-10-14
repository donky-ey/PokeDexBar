import XCTest
@testable import PokeDexBar

/// 조건·결과가 갈리는 간선을 카탈로그가 **다 덮는지.** 데이터가 늘면(새 세대) 여기서 알려 준다.
/// 지금은 각각 2건이고, **0이 아닌 것을 확인했다** — 한 번도 안 걸리는 가드는 장식이다.
///
/// 간선 목록은 `scripts/generate-evolution-form-edges.py` 가 PokéAPI 540체인에서 뽑는다. 세는 기준은
/// "필드가 있다"가 아니라 "앱이 읽는 필드에서 조건이 폼마다 갈린다"다 — 존재로 세면 47건이 나오는데
/// 대부분 같은 조건을 폼 수만큼 되풀이할 뿐이다(스크립트 독스트링).
final class EvolutionFormCoverageTests: XCTestCase {
    private struct ItemEdge: Decodable { let from: Int; let to: Int; let items: [String] }
    private struct FormEdge: Decodable { let from: Int; let to: Int; let forms: [String] }
    private struct Fixture: Decodable { let itemDecides: [ItemEdge]; let formDecides: [FormEdge] }

    private func fixture() throws -> Fixture {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "form-split-edges", withExtension: "json",
                              subdirectory: "EvolutionForms"),
            "픽스처가 없다 — Package.swift 의 resources 에 Fixtures/EvolutionForms 가 있는지 보라")
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    /// 종 id 가 카탈로그에 있다는 것만 보면 PokéAPI 가 사탕공예를 하나 더 얹어도 통과한다(869 는 이미
    /// 있으니까) — 픽스처가 간선마다 들고 있는 **도구 목록**을 한 개씩 카탈로그 행과 대조한다.
    /// 이름이 `EvolutionItem` 에 없는 것도 같은 실패다(앱이 그 도구를 모른다).
    func testEveryItemDecidedEdgeIsCatalogued() throws {
        for edge in try fixture().itemDecides {
            XCTAssertFalse(edge.items.isEmpty, "#\(edge.from)→#\(edge.to) 의 도구 목록이 비었다")
            for name in edge.items {
                guard let item = EvolutionItem.named(name) else {
                    XCTFail("#\(edge.from)→#\(edge.to) 의 \(name) 을 EvolutionItem 이 모른다")
                    continue
                }
                XCTAssertTrue(
                    EvolvedFormCatalog.all.contains { $0.speciesID == edge.to && $0.item == item },
                    "#\(edge.from)→#\(edge.to) 의 \(name) 이 EvolvedFormCatalog 에 없다 — 이 도구가 정할 모습을 아무도 안 정했다")
            }
            // 반대 방향 — 카탈로그에만 있고 PokéAPI 에는 없는 도구는 받을 수 없는 행이다.
            let catalogued = Set(EvolvedFormCatalog.all.filter { $0.speciesID == edge.to }.map(\.item.rawValue))
            XCTAssertEqual(catalogued, Set(edge.items), "#\(edge.to) 의 카탈로그 도구와 픽스처 도구가 다르다")
        }
    }

    /// 픽스처의 폼 이름 각각이 부모의 태생 모습으로 읽히는지. 읽는 규칙은 파서가 쓰는 것
    /// (`PokeAPIClient.formVariantKey` — 접미사 대조)을 **그대로 부른다** — 여기서 따로 쓰면 둘이 갈린다.
    /// 변종에 안 걸리는 이름은 부모의 흔한 모습이며 카탈로그에는 *항목 없음* 으로 표현된다. 그런 이름이
    /// 하나보다 많으면 카탈로그가 모르는 모습이 생긴 것이다(데인차의 세 번째 모습).
    func testEveryFormDecidedEdgeHasBirthForms() throws {
        for edge in try fixture().formDecides {
            let catalogued = Set(BirthFormCatalog.forms(speciesID: edge.from).map(\.variant))
            XCTAssertFalse(catalogued.isEmpty, "#\(edge.from) 의 태생 모습이 없다 — 조건을 가를 축이 없다")
            var matched = Set<String>()
            var common: [String] = []
            for name in edge.forms {
                let detail = PokeAPIClient.detailForTesting(requiredForm: name)
                if let key = PokeAPIClient.formVariantKey(detail, parentSpeciesID: edge.from) {
                    matched.insert(key)
                } else {
                    common.append(name)
                }
            }
            XCTAssertEqual(common.count, 1,
                           "#\(edge.from) 에 카탈로그가 모르는 모습이 있다(흔한 모습은 하나뿐): \(common)")
            // 반대 방향 — 카탈로그 변종이 PokéAPI 응답에 안 나오면 그 키의 조건은 영영 안 만들어진다.
            XCTAssertEqual(matched, catalogued, "#\(edge.from) 의 카탈로그 변종과 픽스처 폼이 다르다")
        }
    }

    func testTheSweepFoundSomething() throws {
        XCTAssertFalse(try fixture().itemDecides.isEmpty)
        XCTAssertFalse(try fixture().formDecides.isEmpty)
    }
}
