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
    func testCurrentClaudeStandardRates() {
        // https://platform.claude.com/docs/en/about-claude/pricing — base input, output, 5m cache write, cache read.
        XCTAssertEqual(ModelPricing.rate(for: "claude-opus-5"), .perMillion(5, 25, 6.25, 0.5))
        XCTAssertEqual(ModelPricing.rate(for: "claude-opus-5-5"), .perMillion(4, 20, 5, 0.2))
        XCTAssertEqual(ModelPricing.rate(for: "claude-sonnet-5"), .perMillion(2, 10, 2.5, 0.2))
        XCTAssertEqual(ModelPricing.rate(for: "claude-sonnet-5-5"), .perMillion(2, 10, 2.5, 0.2))
    }

    /// 최종리뷰 지적 — #289 폴백 제거 후 **실사용 모델이 미가격**으로 남았다: Gemini 3.x(현역
    /// CLI 세대)와 claude-haiku-5-5(실 로그 91행). 폴백 복원이 아니라 정확 행으로 채운다.
    /// 단가 출처(2026-10-15 확인): https://ai.google.dev/gemini-api/docs/pricing ·
    /// https://platform.claude.com/docs/en/about-claude/pricing
    func testGemini3FamilyAndHaiku55AreExactlyPriced() throws {
        XCTAssertEqual(ModelPricing.rate(for: "gemini-3.1-pro-preview"), .perMillion(2, 12, 0, 0.2))
        XCTAssertEqual(ModelPricing.rate(for: "gemini-3.1-flash-lite"), .perMillion(0.25, 1.5, 0, 0.025))
        XCTAssertEqual(ModelPricing.rate(for: "gemini-3-flash-preview"), .perMillion(0.5, 3, 0, 0.05))
        XCTAssertEqual(ModelPricing.rate(for: "gemini-3.8-flash"), .perMillion(0.75, 3.75, 0, 0.075))
        XCTAssertEqual(ModelPricing.rate(for: "gemini-3.6-flash"), .perMillion(0.75, 3.75, 0, 0.075))
        XCTAssertEqual(ModelPricing.rate(for: "gemini-3.5-flash-lite"), .perMillion(0.3, 2.5, 0, 0.03))
        XCTAssertEqual(ModelPricing.rate(for: "claude-haiku-5-5"), .perMillion(0.1, 0.5, 0.125, 0.01))
        // 3.1 Pro 는 200K 초과 구간이 공식 $4/$18/$0.40 — 기존 long-context 배수(2x 입력·캐시,
        // 1.5x 출력)와 정확히 일치하므로 멤버십 추가로 모델링한다.
        XCTAssertEqual(try XCTUnwrap(ModelPricing.estimatedCost(
            model: "gemini-3.1-pro-preview", input: 200_001, output: 1_000, cacheWrite: 0, cacheRead: 0)),
            200_001.0 * 2e-6 * 2 + 1_000 * 12e-6 * 1.5, accuracy: 1e-9)
    }

    /// GPT-6 세대 요금(upstream #384) — 표 행과 272K 초과 long-context 할증 멤버십, 캐시 단가까지.
    /// (업스트림은 자기 기존 테스트 4곳에 흩어 넣었지만 그 함수들은 포크에 없어 한 곳에 모았다.)
    func testGpt6FrontierRatesAndLongContext() throws {
        XCTAssertEqual(ModelPricing.rate(for: "gpt-6-sol"), .perMillion(2, 10, 2.5, 0.2))
        XCTAssertEqual(ModelPricing.rate(for: "gpt-6.1-sol"), .perMillion(2, 10, 2.5, 0.1))
        XCTAssertEqual(ModelPricing.rate(for: "gpt-6-luna"), .perMillion(0.1, 0.5, 0.125, 0.01))
        XCTAssertEqual(try XCTUnwrap(ModelPricing.estimatedCost(model: "gpt-6-luna", input: 272_001, output: 1_000, cacheWrite: 0, cacheRead: 0)), 0.0551502, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(ModelPricing.estimatedCost(model: "gpt-6-sol", input: 272_001, output: 1_000, cacheWrite: 0, cacheRead: 0)), 1.103004, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(ModelPricing.estimatedCost(model: "gpt-6.1-sol", input: 272_001, output: 1_000, cacheWrite: 0, cacheRead: 0)), 1.103004, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(ModelPricing.estimatedCost(model: "gpt-6-luna", input: 100_000, output: 0, cacheWrite: 0, cacheRead: 0)), 0.01, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(ModelPricing.estimatedCost(model: "gpt-6.1-sol", input: 100_000, output: 1_000, cacheWrite: 10_000, cacheRead: 100_000)), 0.245, accuracy: 1e-12)
        // codex-auto-review 같은 미지 이름은 가족 요금을 빌리지 않는다(#289 원칙 유지).
        XCTAssertNil(ModelPricing.estimatedCost(model: "codex-auto-review", input: 100, output: 20, cacheWrite: 0, cacheRead: 40))
    }

    /// The inverse of `testUnknownNamesNeverBorrowFamilyPrices`: that test guards against a
    /// *wrong* price, this one against *no* price. #289 dropped the model-family fallback
    /// without adding exact rows for the identities it had been covering, so the whole Claude 5
    /// family became unpriced and every Claude cost rendered as "unavailable" (#303) — a table
    /// that only asserts the rows it already contains cannot catch that. Add an identity here
    /// as soon as a provider starts reporting it.
    func testModelsReadFromProviderLogsAreAllPriced() throws {
        // A real Claude Code bucket split: every request logs cache creation and cache reads,
        // so a row without a cache-write rate is unpriced in practice even when its input and
        // output columns are filled in.
        for model in ["claude-opus-5", "claude-opus-5-5", "claude-sonnet-5", "claude-sonnet-5-5",
                      "claude-opus-4-8", "claude-opus-4-7", "claude-haiku-5-5",
                      "claude-sonnet-4-6", "claude-haiku-4-5", "claude-fable-5", "claude-fable-5-1"] {
            let cost = try XCTUnwrap(
                ModelPricing.estimatedCost(model: model, input: 2, output: 175,
                                           cacheWrite: 26_939, cacheRead: 42_676),
                "\(model) resolves to no price — the usage cost row renders as unavailable")
            XCTAssertGreaterThan(cost, 0, model)
        }
    }

    /// Official standard text rates. Flash-Lite is a different SKU from Flash;
    /// leaving it out of the table makes its cost Unavailable.
    func testGemini25FlashLiteUsesOfficialTextRates() throws {
        XCTAssertEqual(ModelPricing.rate(for: "gemini-2.5-flash-lite"), .perMillion(0.10, 0.40, 0, 0.01))
        XCTAssertEqual(ModelPricing.rate(for: "models/gemini-2.5-flash-lite"), .perMillion(0.10, 0.40, 0, 0.01))
        XCTAssertEqual(try XCTUnwrap(ModelPricing.estimatedCost(
            model: "gemini-2.5-flash-lite", input: 1_000_000, output: 0, cacheWrite: 0, cacheRead: 0)), 0.10, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(ModelPricing.estimatedCost(
            model: "gemini-2.5-flash-lite", input: 0, output: 1_000_000, cacheWrite: 0, cacheRead: 0)), 0.40, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(ModelPricing.estimatedCost(
            model: "gemini-2.5-flash-lite", input: 0, output: 0, cacheWrite: 0, cacheRead: 1_000_000)), 0.01, accuracy: 1e-12)
        XCTAssertNil(ModelPricing.estimatedCost(
            model: "gemini-2.5-flash-lite", input: 0, output: 0, cacheWrite: 1, cacheRead: 0),
                     "audio and cache-write rates are not in these logs")
        XCTAssertNil(ModelPricing.estimatedCost(
            model: "gemini-3-flash-lite", input: 1_000_000, output: 0, cacheWrite: 0, cacheRead: 0),
                     "an unknown lite id must not inherit Flash or Flash-Lite rates")
    }

}
