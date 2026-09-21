import XCTest
@testable import PokeDexBar

/// 새 아이템 — 분류·수급처·세대 대응.
final class ItemCatalogTests: XCTestCase {
    /// 뽑기·미션으로만 들어온다. 상점에 서면 이 뽑기를 돌 이유가 사라진다.
    func testTheNewItemsAreNotSoldInTheShop() {
        XCTAssertFalse(ShopItem.massageCoupon.isSold)
        for generation in 1...9 {
            let ticket = ShopItem.generationTicket(for: generation)
            XCTAssertNotNil(ticket, "\(generation)세대 확정권이 없다")
            XCTAssertFalse(ticket!.isSold, "\(generation)세대 확정권이 상점에 선다")
        }
    }

    /// 쓰면 없어지는 것이라 소모품 칸이다 — 부적 칸에 서면 개수를 안 센다.
    func testTheNewItemsAreConsumables() {
        XCTAssertEqual(ShopItem.massageCoupon.category, .consumable)
        XCTAssertTrue(ShopItem.massageCoupon.isConsumable)
        for generation in 1...9 {
            XCTAssertEqual(ShopItem.generationTicket(for: generation)?.category, .consumable)
        }
    }

    /// 세대권 ↔ 세대 번호가 양방향으로 맞물린다. 한쪽만 맞으면 8세대권이 7세대를 연다.
    func testGenerationTicketsRoundTrip() {
        for generation in 1...9 {
            let ticket = ShopItem.generationTicket(for: generation)
            XCTAssertEqual(ticket?.guaranteedGeneration, generation, "\(generation)세대")
        }
        XCTAssertNil(ShopItem.generationTicket(for: 0))
        XCTAssertNil(ShopItem.generationTicket(for: 10))
    }

    /// 세대권이 아닌 것에는 세대가 없다 — 대조군. 없으면 "전부 1을 돌려준다"도 통과한다.
    func testOtherItemsHaveNoGeneration() {
        for item in [ShopItem.expCandy, .massageCoupon, .rareEggTicket, .legendaryEggTicket] {
            XCTAssertNil(item.guaranteedGeneration, "\(item.rawValue)")
        }
    }

    /// 세대권은 **등급을 보장하지 않는다** — 세대만 한정하는 쿠폰이다.
    func testGenerationTicketsGuaranteeNoGrade() {
        for generation in 1...9 {
            XCTAssertNil(ShopItem.generationTicket(for: generation)?.guaranteedGrade)
        }
    }

    /// 모든 언어에 이름과 설명이 있다. 빠지면 그 언어에서 빈 줄이 선다.
    func testEveryNewItemIsNamedInEveryLanguage() {
        var items: [ShopItem] = [.massageCoupon]
        items += (1...9).compactMap { ShopItem.generationTicket(for: $0) }
        for item in items {
            for language in [AppLanguage.ko, .en, .ja] {
                XCTAssertFalse(item.label(language).isEmpty, "\(item.rawValue) \(language) 이름")
                XCTAssertFalse(item.detail(language).isEmpty, "\(item.rawValue) \(language) 설명")
            }
        }
    }

    /// 세대권 아홉 개의 이름이 서로 다르다 — 복사해 붙이며 세대 숫자를 안 고친 것을 잡는다.
    func testGenerationTicketNamesAreDistinct() {
        let names = (1...9).compactMap { ShopItem.generationTicket(for: $0)?.label(.ko) }
        XCTAssertEqual(Set(names).count, 9, "\(names)")
    }
}
