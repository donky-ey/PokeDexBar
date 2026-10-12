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
    /// 이번 달 일별 합계(월초→오늘, 빈 날은 0). monthTotal 과 같은 스캔에서 나오고 같은
    /// periodsOK 를 탄다. nil = 이 프로바이더는 시리즈를 못 낸다.
    var monthDaily: [DailyUsage]?
    var periodsOK = false
    /// 토큰이 있는 가장 최근 엔트리. 주/월 합계와 달리 달력 경계에서 리셋되지 않아, 최근에 썼지만
    /// 오늘은 안 쓴 프로바이더의 탭(과 공식 한도)을 지킨다(upstream #336/#402).
    /// 0토큰 synthetic 레코드는 사용이 아니다 — 설치만 한 프로바이더는 숨은 채로 남는다(#56).
    var lastUsage: Date? = nil
}

extension ProviderEnrichment {
    /// 로컬 로그 프로바이더 공통 조립 — 블록·최근속도·주·월·일별·최근사용을 **한 스캔 결과**에서
    /// 전부 도출한다. 프로바이더마다 복제하던 본문을 한 곳으로 모은 것(upstream #270) — 나중에
    /// 추가되는 필드가 일부 복제본에만 채워지는 부류(#157)를 막는다. SP1 의 lastUsage 5중 복제가
    /// 정확히 그 부류였고 여기로 수렴한다.
    /// 비용은 API 환산이라 모든 프로바이더 동일 — 업스트림의 zeroCost 매개변수는 포크 철학
    /// (균일 환산, `LocalCodexProvider` 주석)과 달라 두지 않는다.
    static func local(entries: [LocalUsageReader.Entry], now: Date = Date()) -> ProviderEnrichment {
        let fmt = LocalUsageReader.localDayFormatter()
        let weekStart = LocalUsageReader.startOfWeek(now)
        let monthStart = LocalUsageReader.startOfMonth(now)

        var result = ProviderEnrichment()
        // 블록(burn rate) 계산은 프로바이더 공통 — companion 리듬이 전 프로바이더를 따른다.
        result.activeBlock = LocalUsageReader.activeBlock(entries: entries, now: now)
        result.recentTokensPerMinute = LocalUsageReader.recentRate(entries: entries, now: now)
        result.blocksOK = true
        result.weekTotal = LocalUsageReader.period(
            entries: entries, periodKey: fmt.string(from: weekStart),
            fromDay: fmt.string(from: weekStart), toDay: fmt.string(from: now))
        result.monthTotal = LocalUsageReader.period(
            entries: entries, periodKey: LocalUsageReader.monthKey(now),
            fromDay: fmt.string(from: monthStart), toDay: fmt.string(from: now))
        result.monthDaily = LocalUsageReader.monthDailySeries(entries: entries, now: now)
        result.periodsOK = true
        // 0토큰 synthetic 레코드는 사용이 아니다(#56) — 설치만 한 프로바이더는 숨은 채로 남는다.
        result.lastUsage = entries.lazy.filter { $0.total > 0 }.map(\.date).max()
        return result
    }
}
