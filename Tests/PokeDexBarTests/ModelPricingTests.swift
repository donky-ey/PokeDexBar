import XCTest
@testable import PokeDexBar

/// 가격표에 없는 모델은 "Unavailable/0원" 외엔 아무 흔적이 없다 — Opus 5.5 가 스크린샷을 받고서야
/// 발견된 부류(upstream #361). 프로세스당 한 번만 로그에 남겨 새 모델이 첫 보고 때 보이게 한다.
final class ModelPricingTests: XCTestCase {
    /// 미가격 모델은 **정체당 한 번**만 보고된다 — `Bucket.add` 는 요청마다 돈다.
    func testUnpricedModelIsReportedOnlyOnFirstSighting() {
        let model = "claude-unpriced-\(UUID().uuidString.lowercased())"
        XCTAssertTrue(ModelPricing.firstUnpricedSighting(model))
        XCTAssertFalse(ModelPricing.firstUnpricedSighting(model))
        XCTAssertFalse(ModelPricing.firstUnpricedSighting("ANTHROPIC/" + model.uppercased()),
                       "가격 조회와 같은 정규화를 거쳐야 같은 모델로 접힌다")
    }

    /// 배선 — `AppLog` 는 swift test 에서 no-op 이라 dedupe 소모로 관측한다.
    /// 미가격 모델 집계는 첫 목격을 소모하고(보고됨), 가격이 **의도된** 모델은 소모하지 않는다.
    func testAggregatingAnUnpricedModelReportsItButNotAPricedOne() {
        func entry(_ model: String) -> LocalUsageReader.Entry {
            LocalUsageReader.Entry(id: UUID().uuidString, date: Date(), localDay: "2026-10-08",
                                   model: model, input: 10, output: 5, cacheWrite: 0, cacheRead: 0)
        }
        let unpriced = "claude-unpriced-\(UUID().uuidString.lowercased())"
        var bucket = LocalUsageReader.Bucket()
        bucket.add(entry(unpriced))
        bucket.add(entry("claude-fable-5"))
        // grok 행은 소스가 비용을 보고한다(ticks) — 명시 비용이 있으면 표 누락이 아니므로 보고 금지.
        var grok = entry("grok-4-fast"); grok.explicitCost = 0.42
        bucket.add(grok)

        XCTAssertFalse(ModelPricing.firstUnpricedSighting(unpriced), "미가격 모델이 보고되지 않았다")
        XCTAssertTrue(ModelPricing.firstUnpricedSighting("claude-fable-5"), "표에 있는 모델이 미가격으로 보고됐다")
        XCTAssertTrue(ModelPricing.firstUnpricedSighting("grok-4-fast"), "명시 비용 행이 미가격으로 보고됐다")
    }
}
