import XCTest
import SwiftUI
@testable import PokeDexBar

/// 아이템 그림 — 무엇을 그리는지의 판정과, 실제로 무언가가 그려지는지.
@MainActor
final class ItemIconTests: XCTestCase {

    // MARK: 무엇을 그리나 (순수 판정)

    func testEachItemPicksItsOwnDrawing() {
        XCTAssertEqual(ItemIcon.drawing(for: .expCandy), .candy)
        XCTAssertEqual(ItemIcon.drawing(for: .massageCoupon), .coupon)
        XCTAssertEqual(ItemIcon.drawing(for: .gen3EggTicket), .generationTicket(3))
        XCTAssertEqual(ItemIcon.drawing(for: .gen9EggTicket), .generationTicket(9))
    }

    /// **등급권은 알 그림으로 넘긴다** — 연출 가운데에 그 등급의 진짜 알이 뜨는 것이 상품 자체를
    /// 보여주는 가장 좋은 그림이라, 새로 그리지 않는다.
    func testGradeTicketsDeferToTheEggArt() {
        XCTAssertEqual(ItemIcon.drawing(for: .rareEggTicket), .egg(.rare))
        XCTAssertEqual(ItemIcon.drawing(for: .epicEggTicket), .egg(.epic))
        XCTAssertEqual(ItemIcon.drawing(for: .legendaryEggTicket), .egg(.legendary))
    }

    /// 이번 범위 밖 품목에는 그림이 없다 — 대조군. 없으면 "전부 사탕을 돌려준다"도 통과한다.
    func testItemsOutsideThisFeatureHaveNoDrawing() {
        for item in [ShopItem.shinyCandy, .megaStone, .shinyCharm, .rainbowCharm] {
            XCTAssertNil(ItemIcon.drawing(for: item), "\(item.rawValue)")
        }
    }

    /// 세대 숫자가 그 티켓의 것과 일치하고 **0 이 나오지 않는다.**
    func testTheGenerationNumberMatchesTheTicket() {
        for generation in 1...9 {
            let ticket = ShopItem.generationTicket(for: generation)!
            XCTAssertEqual(ItemIcon.drawing(for: ticket), .generationTicket(generation))
        }
        for item in ShopItem.allCases {
            if case .generationTicket(let n) = ItemIcon.drawing(for: item) {
                XCTAssertTrue((1...9).contains(n), "\(item.rawValue) 가 \(n)세대를 그린다")
            }
        }
    }

    // MARK: 실제로 그려지나

    /// 그린 결과에 **불투명 픽셀이 있어야 한다.** 빈 `Path` 를 돌려주는 실수는 컴파일도 되고
    /// 테스트도 통과하면서 화면에는 아무것도 안 나온다 — 손으로 그리는 도형의 진짜 위험이다.
    private func opaquePixelCount(_ item: ShopItem, size: CGFloat = 78) throws -> Int {
        let host = NSHostingView(rootView: ItemIcon(item: item, size: size)
            .frame(width: size, height: size))
        host.appearance = NSAppearance(named: .darkAqua)
        host.frame = CGRect(x: 0, y: 0, width: size, height: size)
        host.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.setNeedsDisplay(host.bounds)
        host.displayIfNeeded()
        host.cacheDisplay(in: host.bounds, to: rep)
        var count = 0
        for x in stride(from: 0, to: rep.pixelsWide, by: 2) {
            for y in stride(from: 0, to: rep.pixelsHigh, by: 2) {
                if let color = rep.colorAt(x: x, y: y), color.alphaComponent > 0.1 { count += 1 }
            }
        }
        return count
    }

    /// 그린 결과의 픽셀 버퍼 통째로.
    private func pixels(_ item: ShopItem, size: CGFloat = 78) throws -> Data {
        let host = NSHostingView(rootView: ItemIcon(item: item, size: size)
            .frame(width: size, height: size))
        host.appearance = NSAppearance(named: .darkAqua)
        host.frame = CGRect(x: 0, y: 0, width: size, height: size)
        host.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.setNeedsDisplay(host.bounds)
        host.displayIfNeeded()
        host.cacheDisplay(in: host.bounds, to: rep)
        let bytes = try XCTUnwrap(rep.bitmapData)
        return Data(bytes: bytes, count: rep.bytesPerRow * rep.pixelsHigh)
    }

    func testEveryPrizeInTheBoxActuallyDrawsSomething() throws {
        for entry in ItemDrawBalance.pool {
            let items: [ShopItem]
            switch entry.prize {
            case .item(let item, _): items = [item]
            case .generationTicket: items = (1...9).compactMap { ShopItem.generationTicket(for: $0) }
            }
            for item in items {
                XCTAssertGreaterThan(try opaquePixelCount(item), 50,
                                     "\(item.rawValue) 가 빈 그림이다")
            }
        }
    }

    /// 작은 크기에서도 그려진다. 크기 0 은 **렌더로 물을 수 없다**(0×0 비트맵이 안 만들어진다) —
    /// 그건 아래 도형 테스트가 직접 맡는다.
    func testTinySizesStillDraw() throws {
        for size in [CGFloat(1), 4, 12] {
            for item in [ShopItem.expCandy, .massageCoupon, .gen1EggTicket] {
                XCTAssertNoThrow(try opaquePixelCount(item, size: size), "\(item.rawValue) @\(size)")
            }
        }
    }

    /// **도형 자체에 NaN 이 없다.** 이 저장소는 배율 0·NaN 으로 AppKit 이 프로세스를 abort 시킨
    /// 전례가 있어(`SparklePose.safeScale`), 크기에서 유도하는 산술이 0 을 만나도 값이 성해야 한다.
    /// 픽스처가 아니라 `Path` 에 직접 물어본다.
    func testTheShapesStayFiniteAtEverySize() {
        for size in [CGFloat(0), 0.0001, 1, 78, 4096] {
            let rect = CGRect(x: 0, y: 0, width: size, height: size)
            for box in [CandyShape().path(in: rect).boundingRect,
                        TicketShape().path(in: rect).boundingRect] {
                // 빈 Path 의 boundingRect 는 .null 이다 — 그건 NaN 이 아니라 "비었다"이므로 통과시킨다.
                guard !box.isNull else { continue }
                XCTAssertFalse(box.origin.x.isNaN || box.origin.y.isNaN
                               || box.width.isNaN || box.height.isNaN,
                               "크기 \(size) 에서 NaN 이 나왔다: \(box)")
                XCTAssertTrue(box.width.isFinite && box.height.isFinite, "크기 \(size): \(box)")
            }
        }
    }

    /// 셋이 서로 다른 그림이다 — 같은 도형을 돌려주면 화면에서 구별이 안 된다.
    /// **픽셀 수가 아니라 버퍼를 통째로 비교한다** — 서로 다른 도형이 우연히 같은 개수를 낼 수 있다.
    func testTheThreeDrawingsDifferFromEachOther() throws {
        let buffers = try [ShopItem.expCandy, .massageCoupon, .gen1EggTicket].map {
            try pixels($0)
        }
        XCTAssertEqual(Set(buffers).count, 3, "같은 그림이 나온다")
    }

    /// 세대권끼리도 숫자가 달라 서로 다른 그림이다 — 숫자가 안 그려지면 아홉 장이 전부 같아진다
    /// (실제로 한 번 그랬다: 내용물을 절취선의 오버레이 안에 중첩시켜 숫자가 통째로 빠졌다).
    func testGenerationTicketsDifferFromEachOther() throws {
        let buffers = try (1...9).map { try pixels(ShopItem.generationTicket(for: $0)!) }
        XCTAssertEqual(Set(buffers).count, 9, "세대 숫자가 그림에 안 나타난다")
    }
}
