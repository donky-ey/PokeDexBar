@testable import PokeDexBar

extension PlayerStore {
    /// 프로바이더 하나로 사용량을 넣는다. 원장이 프로바이더별로 바뀌기 전의 호출 모양(`todayTokens:`)을
    /// 쓰는 테스트들이 그대로 돌게 하는 테스트 전용 다리 — 프로바이더가 하나면 두 장부는 같은 값을 낸다
    /// (떨어진 뒤 다시 오르는 경우까지: 둘 다 고점에서 기다린다).
    func update(todayTokens: Int, todayDate: String, hasUsageData: Bool) {
        update(todayTokensByProvider: hasUsageData ? ["claude_code": todayTokens] : [:],
               todayDate: todayDate, hasUsageData: hasUsageData)
    }
}
