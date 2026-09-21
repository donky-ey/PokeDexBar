import Foundation
@testable import PokeDexBar

/// 경계 검증 테스트용 — 임의의 값을 넣은 세이브 JSON 을 **실제 디코더**에 통과시킨다.
/// 손으로 만든 `PlayerState` 는 디코드 경로를 안 지나므로 자르기를 검증하지 못한다.
enum PlayerStateFixture {
    static func decoded(paidItemDraws: Int) throws -> PlayerState {
        let json = "{\"paidItemDraws\": \(paidItemDraws)}"
        return try JSONDecoder().decode(PlayerState.self, from: Data(json.utf8))
    }
}
