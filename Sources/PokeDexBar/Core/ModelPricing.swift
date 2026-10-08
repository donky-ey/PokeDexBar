import Foundation

/// 모델별 토큰 단가(USD/토큰). ccusage(--offline, LiteLLM 스냅샷)의 단가를 실측 역산해 동일하게 번들.
/// 검증: 여러 날 ccusage --breakdown 의 (토큰타입 4종, cost)로 선형 역산 → 적합오차 0.000%.
struct ModelRate: Equatable {
    let input: Double        // USD per token
    let output: Double
    let cacheWrite: Double   // cache creation
    let cacheRead: Double

    static let zero = ModelRate(input: 0, output: 0, cacheWrite: 0, cacheRead: 0)

    /// USD per **million** tokens 로 선언(가독성) → per-token 으로 변환.
    static func perMillion(_ input: Double, _ output: Double, _ cacheWrite: Double, _ cacheRead: Double) -> ModelRate {
        ModelRate(input: input / 1_000_000, output: output / 1_000_000,
                  cacheWrite: cacheWrite / 1_000_000, cacheRead: cacheRead / 1_000_000)
    }
}

enum ModelPricing {
    /// 정확 매칭 테이블 (USD/Mtok). ccusage 와 일치(역산 0% 오차).
    static let table: [String: ModelRate] = [
        "claude-opus-4-8":            .perMillion(5, 25, 6.25, 0.5),
        "claude-opus-4-7":            .perMillion(5, 25, 6.25, 0.5),
        "claude-sonnet-4-6":          .perMillion(3, 15, 3.75, 0.3),
        "claude-haiku-4-5-20251001":  .perMillion(1, 5, 1.25, 0.1),
        "claude-fable-5":             .perMillion(10, 50, 12.5, 1.0), // LiteLLM 스냅샷 가격 등재됨(2026-08) — 기존 미가격 $0 플레이스홀더 대체
        // Fable 5.1: 기본 요율은 Fable 5 와 같고 캐시 읽기만 $0.25/MTok (0.025× input).
        // 이 행이 없으면 fable 패밀리 폴백이 Fable 5 의 $1.00 을 적용해 비용을 4배 과대표시한다(#277).
        "claude-fable-5-1":           .perMillion(10, 50, 12.5, 0.25),
        "gpt-5.5":                    .perMillion(5, 30, 0, 0.5),
        // Gemini — 공식 API 단가(기본 티어, ≤200K 프롬프트). 캐시는 read 단가만(스토리지 시간요금 제외).
        "gemini-2.5-pro":             .perMillion(1.25, 10, 0, 0.3125),
        "gemini-2.5-flash":           .perMillion(0.30, 2.5, 0, 0.075),
        "gemini-2.0-flash":           .perMillion(0.10, 0.4, 0, 0.025),
    ]

    /// 모델명 → 단가. 정확 매칭 우선, 없으면 패밀리(opus/sonnet/haiku/gpt) 폴백(버전 드리프트 대비),
    /// 그래도 없으면 0(ccusage 가 미가격 모델을 0 으로 처리하는 것과 동일).
    static func rate(for model: String) -> ModelRate {
        if let r = table[model] { return r }
        let m = model.lowercased()
        // Grok 은 서버가 보고한 비용(costUsdTicks)만 쓴다 — 단가표가 없으므로 0. 아래 패밀리 폴백보다
        // 먼저 끊어야 `grok-codex-*`·`grok-4o-*` 류 이름이 GPT 단가로 잡혀 가짜 금액을 표시하지 않는다.
        if m.hasPrefix("grok") { return .zero }
        if m.contains("opus")   { return .perMillion(5, 25, 6.25, 0.5) }
        if m.contains("sonnet") { return .perMillion(3, 15, 3.75, 0.3) }
        if m.contains("haiku")  { return .perMillion(1, 5, 1.25, 0.1) }
        if m.contains("gpt") || m.contains("codex") || m.contains("o4") || m.contains("o3") {
            return .perMillion(5, 30, 0, 0.5)
        }
        // Gemini 패밀리 폴백 — pro/flash 만(버전 드리프트 대비). 그 외 gemini 변형은 0(오표시 방지).
        if m.hasPrefix("gemini") {
            if m.contains("pro")   { return .perMillion(1.25, 10, 0, 0.3125) }
            if m.contains("flash") { return .perMillion(0.30, 2.5, 0, 0.075) }
        }
        return .zero
    }

    /// 이 모델에 **의도된** 가격이 있는가 — 표의 행 또는 패밀리 폴백(grok 의 .zero 포함).
    /// 어느 쪽도 아니면 미가격이고, 비용이 조용히 0 으로 집계된다.
    static func hasIntendedPrice(for model: String) -> Bool {
        if table[model] != nil { return true }
        let m = model.lowercased()
        return m.hasPrefix("grok") || m.contains("opus") || m.contains("sonnet") || m.contains("haiku")
            || m.contains("gpt") || m.contains("codex") || m.contains("o4") || m.contains("o3")
            || (m.hasPrefix("gemini") && (m.contains("pro") || m.contains("flash")))
    }

    /// 표가 가격을 못 매기는 모델은 "0원" 말고는 흔적이 없다(upstream #361 — Opus 5.5 가
    /// 스크린샷을 받고서야 발견). 정체당 한 번만 로그에 남겨 새 모델이 보이게 한다.
    static func noteUnpriced(_ model: String) {
        guard firstUnpricedSighting(model) else { return }
        AppLog.write("Unpriced model: \(model) — ModelPricing.table 에 행이 생길 때까지 비용이 0 으로 집계된다")
    }

    /// `model` 을 처음 봤을 때만 true — `noteUnpriced` 의 dedupe. 정규화는 가격 조회와 맞춘다
    /// (소문자 + 프로바이더 접두 제거: "ANTHROPIC/X" 와 "x" 는 같은 모델).
    static func firstUnpricedSighting(_ model: String) -> Bool {
        let key = model.lowercased().split(separator: "/").last.map(String.init) ?? model.lowercased()
        unpricedLock.lock(); defer { unpricedLock.unlock() }
        return unpricedSeen.insert(key).inserted
    }

    nonisolated(unsafe) private static var unpricedSeen: Set<String> = []
    private static let unpricedLock = NSLock()

    static func cost(model: String, input: Int, output: Int, cacheWrite: Int, cacheRead: Int) -> Double {
        let r = rate(for: model)
        return Double(input) * r.input
            + Double(output) * r.output
            + Double(cacheWrite) * r.cacheWrite
            + Double(cacheRead) * r.cacheRead
    }
}
