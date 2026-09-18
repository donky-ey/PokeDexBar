import XCTest
import SwiftUI
@testable import PokeDexBar

/// 아이템 연출 — 그림 선택과 가림.
@MainActor
final class ItemRevealTests: XCTestCase {
    private static let size = CGSize(width: PopoverMetrics.width, height: 220)

    private func result(_ item: ShopItem, _ rarity: Grade) -> ItemDrawResult {
        ItemDrawResult(prize: .item(item, 1), item: item, count: 1, rarity: rarity)
    }

    /// **쓰는 심볼이 실제로 만들어지는지 API 에 물어본다.** 픽스처가 아니라 그 API 에 묻는
    /// 방식은 이 저장소가 특이행렬 사건에서 택한 것과 같다 — 없는 심볼은 조용히 빈 자리가 된다.
    func testEverySymbolExists() throws {
        for item in ShopItem.allCases {
            guard let name = ItemRevealView.symbolName(for: item) else { continue }
            XCTAssertNotNil(NSImage(systemSymbolName: name, accessibilityDescription: nil),
                            "\(item.rawValue) 의 심볼 \(name) 이 없다")
        }
    }

    /// 알 확정권은 심볼이 아니라 **그 등급의 알 그림**을 쓴다 — 이미 있는 그림이 더 말이 된다.
    func testEggTicketsUseEggArtNotASymbol() {
        for item in [ShopItem.rareEggTicket, .epicEggTicket, .legendaryEggTicket] {
            XCTAssertNil(ItemRevealView.symbolName(for: item), "\(item.rawValue)")
        }
    }

    /// 심볼을 쓰는 것에는 반드시 이름이 있다 — 없으면 아무것도 안 그려진다.
    func testSymbolItemsHaveAName() {
        XCTAssertNotNil(ItemRevealView.symbolName(for: .expCandy))
        XCTAssertNotNil(ItemRevealView.symbolName(for: .massageCoupon))
    }

    private func pixels(behind: Color, item: ShopItem, rarity: Grade) throws -> Data {
        let view = ZStack {
            behind
            ItemRevealView(result: result(item, rarity), l: L(.ko), language: .ko, onDone: {})
        }
        .frame(width: Self.size.width, height: Self.size.height)
        let host = NSHostingView(rootView: view)
        host.appearance = NSAppearance(named: .darkAqua)
        host.frame = CGRect(origin: .zero, size: Self.size)
        host.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.setNeedsDisplay(host.bounds)
        host.displayIfNeeded()
        host.cacheDisplay(in: host.bounds, to: rep)
        let bytes = try XCTUnwrap(rep.bitmapData)
        return Data(bytes: bytes, count: rep.bytesPerRow * rep.pixelsHigh)
    }

    /// 알 연출과 같은 규칙 — 뒤에 무엇을 깔든 결과가 같아야 한다. 비치면 결과를 미리 안다.
    func testTheItemRevealHidesWhateverIsBehindIt() throws {
        let overMagenta = try pixels(behind: Color(red: 1, green: 0, blue: 1),
                                     item: .legendaryEggTicket, rarity: .legendary)
        let overBlack = try pixels(behind: .black, item: .legendaryEggTicket, rarity: .legendary)
        XCTAssertFalse(overMagenta.isEmpty)
        XCTAssertEqual(overMagenta, overBlack, "아이템 연출 뒤가 비친다")
    }
}
