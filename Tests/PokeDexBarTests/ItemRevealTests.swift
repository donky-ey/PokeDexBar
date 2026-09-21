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
