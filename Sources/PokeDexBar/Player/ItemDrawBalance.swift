import Foundation

/// 박사의 상자 — 값·확률·효과량. 화면과 스토어가 이 한 곳에서 값을 읽는다.
enum ItemDrawBalance {
    /// 마사지 쿠폰 한 장이 올려 주는 친밀도(초). 하루치이고, 친밀도 진화 문턱과 같은 값이다
    /// (`EvoRequirement.friendshipSeconds`). 쓰다듬기로는 8분이면 같은 양이 나온다.
    static let massageSeconds = 86_400
}
