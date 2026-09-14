import XCTest
import SwiftUI
@testable import PokeDexBar

/// 뽑기 연출이 **뒤를 가리는지**. 연출이 부화칸 줄 위에서 나기 시작하면서, 반투명 배경 틈으로
/// 방금 놓인 알의 등급색이 비쳐 **연출이 끝나기 전에 결과를 알 수 있었다**(사용자 지적).
/// 상점에 있을 땐 뒤가 상점 목록이라 흘릴 것이 없어 아무도 못 봤다.
@MainActor
final class DrawRevealCoverTests: XCTestCase {
    private static let size = CGSize(width: PopoverMetrics.width, height: 220)

    /// 연출 한 장을 그린다 — `behind` 는 뒤에 깔 색이다.
    private func pixels(behind: Color) throws -> Data {
        let view = ZStack {
            behind
            EggRevealView(grade: .legendary, shiny: true, l: L(.ko),
                          language: .ko, onDone: {})
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

    /// **뒤에 무엇을 깔든 결과가 같아야 한다** — 한 픽셀이라도 뒷색을 따라가면 그만큼 비친다.
    /// 색을 하나 정해 "그 색이 없다"로 물으면 연출 자체의 색과 구별이 안 되므로, 두 장을 비교한다.
    func testTheRevealHidesWhateverIsBehindIt() throws {
        let overMagenta = try pixels(behind: Color(red: 1, green: 0, blue: 1))
        let overBlack = try pixels(behind: .black)
        XCTAssertFalse(overMagenta.isEmpty, "아무것도 안 그려졌다 — 비교가 무의미하다")
        XCTAssertEqual(overMagenta, overBlack, "연출 뒤가 비친다 — 알 목록이 읽힌다")
    }

    /// 대조군: 같은 방법으로 **가리지 않는** 표면은 뒷색을 따라가야 한다. 없으면 "렌더가 늘
    /// 같은 그림을 준다"(예: 캐시가 굳거나 아무것도 안 그려짐)여도 위가 통과한다.
    func testTheComparisonCanActuallySeeThrough() throws {
        func translucent(_ behind: Color) throws -> Data {
            let view = ZStack { behind; Color.black.opacity(0.93) }
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
        XCTAssertNotEqual(try translucent(Color(red: 1, green: 0, blue: 1)),
                          try translucent(.black),
                          "7% 반투명도 못 가려내면 이 비교는 아무것도 못 잡는다")
    }
}
