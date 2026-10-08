import Foundation

/// provider 확장 포인트 — 새 소스(Gemini/OpenCode 등)는 이 protocol 구현체 추가만으로 확장
protocol UsageProvider: Sendable {
    var id: String { get }
    var displayName: String { get }
    /// Whether this provider contributes to cost aggregates / per-row cost UI.
    /// Flat-rate subscriptions (e.g. Cursor) report tokens only.
    var reportsCost: Bool { get }

    /// 오늘 합계 (critical path) — 메뉴바 숫자와 stale 판정의 기준.
    /// 데이터 소스 자체가 없거나 오늘 사용량이 없으면 nil.
    func fetchDaily() async throws -> DailyUsage?

    /// 블록/주월 누적 상세 (best effort) — 느리거나 실패해도 메뉴바 숫자에 영향 없음.
    func fetchEnrichment() async -> ProviderEnrichment
}

extension UsageProvider {
    var reportsCost: Bool { true }
}

/// 부가 정보 수집 결과. *OK 플래그가 false 면 수집 실패 → 이전 값 유지.
struct ProviderEnrichment: Sendable {
    var activeBlock: BlockUsage?
    /// 최근 몇 분의 분당 토큰(`LocalUsageReader.recentRate`). 블록과 같은 스캔에서 나오므로
    /// `blocksOK` 를 함께 탄다 — 실패하면 이전 값을 유지한다.
    var recentTokensPerMinute: Double = 0
    var blocksOK = false
    var weekTotal: PeriodUsage?
    var monthTotal: PeriodUsage?
    var periodsOK = false
    /// 토큰이 있는 가장 최근 엔트리. 주/월 합계와 달리 달력 경계에서 리셋되지 않아, 최근에 썼지만
    /// 오늘은 안 쓴 프로바이더의 탭(과 공식 한도)을 지킨다(upstream #336/#402).
    /// 0토큰 synthetic 레코드는 사용이 아니다 — 설치만 한 프로바이더는 숨은 채로 남는다(#56).
    var lastUsage: Date? = nil
}
