import Foundation

/// 박사의 상자 — 값·확률·효과량. 화면과 스토어가 이 한 곳에서 값을 읽는다.
enum ItemDrawBalance {
    /// 마사지 쿠폰 한 장이 올려 주는 친밀도(초). 하루치이고, 친밀도 진화 문턱과 같은 값이다
    /// (`EvoRequirement.friendshipSeconds`). 쓰다듬기로는 8분이면 같은 양이 나온다.
    static let massageSeconds = 86_400
}

/// 상자에서 나오는 것. 세대권은 뽑는 순간 세대를 굴리므로 표에 아홉 줄을 세우지 않는다.
enum ItemPrize: Equatable, Sendable {
    case item(ShopItem, Int)
    case generationTicket
}

extension ItemDrawBalance {
    /// 상품 한 줄. `weight` 는 **정수 천분율**이고 이것이 유일한 선언이다.
    struct Entry: Sendable {
        let prize: ItemPrize
        let weight: Int
        /// 연출 단계 — 알 뽑기와 같은 사다리를 쓴다.
        let rarity: Grade
    }

    /// 하루 첫 판 다음부터의 값 사다리. 그날 안에서 두 배씩 오른다.
    ///
    /// **값을 고정하면 경제가 뚫린다.** 포인트는 개체 방출로 버는데, 알 하나(1천만 토큰)에서
    /// 나온 안 키운 커먼이 2점이라 1천만 토큰 ≈ 2~3점이다. 값이 20 고정이면 한 판의 입력이
    /// 약 8천만 토큰인데 이 풀의 기대값은 그보다 크고, 3슬롯 × 30분이면 하루 100~150점이
    /// 나와 하루 일곱 판까지 도는 순환이 생긴다. 두 배씩 오르면 같은 사람이 네 판에서 멈춘다.
    static let ladder = DoublingLadder(base: 20)

    /// 확률표. 합은 정확히 1000‰ 이고 테스트가 그것을 잠근다.
    ///
    /// **반짝이는 사탕은 없다** — 게임 전체를 통틀어 2개라는 결정이 이미 있다(`DexMissions.all`).
    static let pool: [Entry] = [
        Entry(prize: .item(.expCandy, 1),           weight: 340, rarity: .common),
        Entry(prize: .item(.massageCoupon, 1),      weight: 300, rarity: .common),
        Entry(prize: .generationTicket,             weight: 180, rarity: .rare),
        Entry(prize: .item(.rareEggTicket, 1),      weight: 120, rarity: .rare),
        Entry(prize: .item(.epicEggTicket, 1),      weight:  45, rarity: .epic),
        Entry(prize: .item(.legendaryEggTicket, 1), weight:  15, rarity: .legendary),
    ]

    /// 0…1 굴림 → 상품. **정수 천분율 공간에서 누적한다** — 소수로 누적하면 이진 소수에서
    /// 오차가 쌓여 경계 바로 위 값이 한 줄 아래로 샌다(`EggBalance.rollGrade` 와 같은 이유).
    static func roll(_ roll: Double) -> Entry {
        let clamped = min(1, max(0, roll))
        let scaled = Int(clamped * 1000)
        var cumulative = 0
        for entry in pool {
            cumulative += entry.weight
            if scaled < cumulative { return entry }
        }
        return pool.last!   // 반올림 여분으로 끝까지 온 경우
    }
}
