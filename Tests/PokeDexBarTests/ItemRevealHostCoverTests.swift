import XCTest
import SwiftUI
@testable import PokeDexBar

/// 아이템 연출이 **실제로 얹히는 자리**(상점 탭, 320pt)에서도 뒤를 가리는지.
///
/// `ItemRevealTests.testTheItemRevealHidesWhateverIsBehindIt` 은 `ItemRevealView` 를 220pt 의
/// 넉넉한 틀에 직접 띄워 통과했다 — 하지만 그건 이 연출이 실제로 얹히던 자리가 아니었다. 진짜
/// 자리는 한때 `ProfessorBoxSection` 자체(52pt 남짓)였고, `RevealTheater` 무대(150pt + 결과줄)가
/// 그 자리보다 커서 뒤 목록(상점 품목줄)이 비쳤다 — 딥리뷰가 잡은 결함이고, v1.16.2 에서 이미 한
/// 번 겪은 회귀(반투명 배경이 비쳐 결과를 미리 알 수 있었다)와 같은 부류다. 지금은 `ShopTabView`
/// 의 탭 프레임(320pt) 위에 얹는다(`ShopTabView.swift` 의 `.overlay` 참고) — 그 실제 마운트
/// 지점을 그대로 렌더해서 잰다. `DrawRevealCoverTests`(알 뽑기 쪽의 같은 종류 테스트)를 본떴다.
@MainActor
final class ItemRevealHostCoverTests: XCTestCase {
    private static let width = PopoverMetrics.width
    /// `ShopTabView.body` 의 `.frame(height: 320)` 과 같은 값이다.
    private static let tabHeight: CGFloat = 320
    /// 옛 마운트 자리(`ProfessorBoxSection`)의 실측 높이 — 딥리뷰가 잰 값("52pt 남짓").
    private static let oldSectionHeight: CGFloat = 52

    private struct StubProvider: PokeProviding {
        func line(baseSpeciesID: Int) async throws -> EvoLine {
            EvoLine(baseID: baseSpeciesID, tree: EvoNode(speciesID: baseSpeciesID, children: []),
                    rarity: .common, names: [:])
        }
        func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
        func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
    }

    private func makeStore() -> PlayerStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("itemreveal-host-\(UUID().uuidString).json")
        return PlayerStore(fileURL: url, rng: SeededRNG(seed: 5),
                           now: { Date(timeIntervalSince1970: 1_700_000_000) })
    }

    private func result() -> ItemDrawResult {
        ItemDrawResult(prize: .item(.expCandy, 1), item: .expCandy, count: 1, rarity: .legendary)
    }

    private func render(_ view: some View, size: CGSize) throws -> Data {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        host.appearance = NSAppearance(named: .darkAqua)
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.setNeedsDisplay(host.bounds)
        host.displayIfNeeded()
        host.cacheDisplay(in: host.bounds, to: rep)
        let bytes = try XCTUnwrap(rep.bitmapData)
        return Data(bytes: bytes, count: rep.bytesPerRow * rep.pixelsHigh)
    }

    /// 실제 상점 탭을 그린다. `itemRevealForTesting` 은 뽑기 버튼을 누르지 않고 연출이 뜬 상태로
    /// 시작하는 테스트 전용 통로다(`ShopTabView` 의 `#if DEBUG` 이니셜라이저).
    private func shopTabPixels(behind: Color) throws -> Data {
        let view = ZStack {
            behind
            ShopTabView(store: makeStore(), provider: StubProvider(), itemRevealForTesting: result())
        }
        return try render(view, size: CGSize(width: Self.width, height: Self.tabHeight))
    }

    /// **진짜 마운트 지점 — 이게 영구 회귀 가드다.** 뒤에 무엇을 깔든 결과가 같아야 한다.
    func testTheRealShopTabMountHidesWhateverIsBehindIt() throws {
        let overMagenta = try shopTabPixels(behind: Color(red: 1, green: 0, blue: 1))
        let overBlack = try shopTabPixels(behind: .black)
        XCTAssertFalse(overMagenta.isEmpty, "아무것도 안 그려졌다 — 비교가 무의미하다")
        XCTAssertEqual(overMagenta, overBlack, "상점 탭의 실제 자리에서 아이템 연출 뒤가 비친다")
    }

    /// 대조군 — 옛 자리(52pt)에 그대로 띄웠으면 **지금도** 샌다는 것을 보여준다. `RevealTheater`
    /// 자체는 이 수정으로 안 바뀌었다(마운트 위치만 옮겼다) — 이 대조군이 없으면 위 테스트가
    /// 통과하는 이유가 "연출이 고쳐져서"인지 "비교 방법이 원래 아무것도 못 잡아서"인지 구별이
    /// 안 된다(`DrawRevealCoverTests.testTheComparisonCanActuallySeeThrough` 와 같은 이유).
    ///
    /// **52pt 짜리 틀을 캔버스 전체로 쓰면 안 된다** — 그러면 무대가 넘치는 부분이 루트
    /// `NSHostingView` 자체의 경계 밖이라 그려질 표면이 없어 그냥 안 보인다(클리핑과 새는 것은
    /// 다르다). 진짜 버그는 **더 큰 캔버스 안에서** 52pt 짜리 작은 구역에 얹었을 때, 그 구역보다
    /// 큰 무대가 옆 줄들의 자리로 넘쳐 그린다는 것이다 — 그래서 위아래에 `Spacer` 를 두어 그 큰
    /// 캔버스 속 작은 구역을 흉내 낸다(`ProfessorBoxSection` 이 상점 스크롤 안에서 그랬던 그대로).
    func testTheOldSmallHostStillLeaksIfMountedThere() throws {
        func pixels(behind: Color) throws -> Data {
            let smallSection = Color.clear
                .frame(width: Self.width, height: Self.oldSectionHeight)
                .overlay {
                    ItemRevealView(result: result(), l: L(.ko), language: .ko, onDone: {})
                }
            let view = ZStack {
                behind
                VStack(spacing: 0) {
                    Spacer()
                    smallSection
                    Spacer()
                }
            }
            return try render(view, size: CGSize(width: Self.width, height: Self.tabHeight))
        }
        let overMagenta = try pixels(behind: Color(red: 1, green: 0, blue: 1))
        let overBlack = try pixels(behind: .black)
        XCTAssertNotEqual(overMagenta, overBlack,
                          "52pt 자리에서도 안 샌다면 이 비교 방법이 애초에 아무것도 못 잡는다")
    }
}
