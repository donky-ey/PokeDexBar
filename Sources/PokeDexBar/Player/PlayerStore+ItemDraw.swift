import Foundation

/// 한 판의 결과 — 화면이 연출에 그대로 넘긴다.
struct ItemDrawResult: Equatable, Sendable {
    let prize: ItemPrize
    /// 실제로 가방에 들어간 물건. 세대권은 여기서 세대가 정해져 있다.
    let item: ShopItem
    let count: Int
    let rarity: Grade
}

/// 박사의 상자 — 아이템 뽑기와 거기서 나오는 것들의 사용.
extension PlayerStore {
    /// 오늘 무료 판이 남았나.
    var itemDrawIsFree: Bool { !state.freeItemDrawUsed }

    /// 다음 판의 값. 무료면 0, 사다리 상한을 넘었으면 nil(더 못 뽑는다).
    var nextItemDrawPrice: Int? {
        if itemDrawIsFree { return 0 }
        return ItemDrawBalance.ladder.price(step: state.paidItemDraws + 1)
    }

    /// **이 판 다음** 판의 값. 각주가 사다리를 미리 말할 때 쓴다 — 지금 값이 아니라 다음 값을
    /// 보여야 "두 배씩 오른다"가 숫자로 읽힌다. 상한을 넘으면 nil.
    var itemDrawPriceAfterNext: Int? {
        // 무료 판을 쓰고 나면 유료 1단계가 다음이고, 유료 n 판을 썼으면 n+2 단계가 다음이다.
        let step = itemDrawIsFree ? 1 : state.paidItemDraws + 2
        return ItemDrawBalance.ladder.price(step: step)
    }

    /// 지금 뽑을 수 있나 — 화면의 버튼이 이 하나만 본다.
    var canDrawItem: Bool {
        guard let price = nextItemDrawPrice else { return false }
        return state.researchPoints >= price
    }

    /// 한 판 뽑는다. 못 뽑으면 nil 이고 **아무것도 차감하지 않는다**(제안 데려오기와 같은 규칙).
    ///
    /// 차감·지급·카운터를 한 `mutate` 안에서 한다 — 갈라 두면 "포인트는 줄었는데 물건이 없다"
    /// 나 그 반대가 생긴다(`redeemEggTicket` 이 같은 이유로 한 함수다).
    @discardableResult
    func drawItem() -> ItemDrawResult? {
        guard let price = nextItemDrawPrice, state.researchPoints >= price else { return nil }
        let free = itemDrawIsFree
        let entry = ItemDrawBalance.roll(nextRandomUnit())
        let item: ShopItem
        let count: Int
        switch entry.prize {
        case .item(let shopItem, let n):
            item = shopItem
            count = n
        case .generationTicket:
            // 세대는 여기서 굴린다 — 아홉 세대 균등.
            let generation = 1 + Int(nextRandomUnit() * 9) % 9
            guard let ticket = ShopItem.generationTicket(for: generation) else { return nil }
            item = ticket
            count = 1
        }
        mutate {
            $0.researchPoints -= price
            if free { $0.freeItemDrawUsed = true } else { $0.paidItemDraws += 1 }
            $0.inventory[item.rawValue, default: 0] += count
        }
        return ItemDrawResult(prize: entry.prize, item: item, count: count, rarity: entry.rarity)
    }
}

/// 박사의 상자 — 아이템 뽑기 결과의 사용(마사지 쿠폰 등).
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
