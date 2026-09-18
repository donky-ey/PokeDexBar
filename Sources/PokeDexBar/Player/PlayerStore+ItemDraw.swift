import Foundation

/// 박사의 상자 — 아이템 뽑기와 거기서 나오는 것들의 사용.
extension PlayerStore {
    /// 마사지 쿠폰 한 장을 쓴다. 그 아이와 **함께한 시간**을 24시간 늘린다.
    ///
    /// `partnerSeconds` 가 아니라 `pettedSeconds` 에 담는 이유는 쓰다듬기와 같다 — 파트너
    /// 시간에 더하면 화면의 "함께한 시간" 까지 늘어 실제로 곁에 있던 시간을 거짓으로 말한다.
    /// 문턱 판정만 `bondDuration` 이 둘을 합쳐 본다.
    ///
    /// 차감과 적용이 한 `mutate` 안에 있다 — 갈라 두면 "쿠폰은 없어졌는데 안 올랐다" 가 난다.
    @discardableResult
    func useMassageCoupon(on individualID: UUID) -> Bool {
        guard count(of: .massageCoupon) > 0,
              let index = state.box.firstIndex(where: { $0.id == individualID }) else { return false }
        mutate {
            $0.box[index].pettedSeconds += ItemDrawBalance.massageSeconds
            Self.consume(.massageCoupon, in: &$0)
        }
        return true
    }
}
