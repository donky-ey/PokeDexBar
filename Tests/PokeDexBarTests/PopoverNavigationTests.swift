import XCTest
@testable import PokeDexBar

// 팝오버 내비게이션 리셋 계약 — 닫혔다 열릴 때 AppDelegate.togglePopover 가 reset()을 불러
// 항상 Home 으로 돌아가게 한다(설정 화면 잔류 방지).
@MainActor
final class PopoverNavigationTests: XCTestCase {
    func testDefaultsToHome() {
        let nav = PopoverNavigation()
        XCTAssertFalse(nav.showSettings)
        XCTAssertEqual(nav.tab, .home)
    }

    func testResetReturnsToHomeFromSettings() {
        let nav = PopoverNavigation()
        nav.showSettings = true
        nav.tab = .collection
        nav.reset()
        XCTAssertFalse(nav.showSettings)   // 설정 화면 닫힘
        XCTAssertEqual(nav.tab, .home)     // 탭도 Home 으로
    }

    /// #301: Hide is a right-click. Show has to live on the popover footer, bound to the same
    /// `floatingPetEnabled` the Settings checkbox already uses. Removing the button must fail this.
    func testPopoverFooterTogglesFloatingPetWithoutOpeningSettings() throws {
        let source = try String(contentsOf: Self.popoverSource, encoding: .utf8)
        let footer = try XCTUnwrap(source.range(of: "private var footer"))
        let body = String(source[footer.lowerBound...])
        XCTAssertTrue(
            body.contains("store.floatingPetEnabled.toggle()"),
            "footer must flip floatingPetEnabled — Hide already does; Show had only Settings")
        XCTAssertTrue(body.contains("l.floatingPetHideLabel"))
        XCTAssertTrue(body.contains("l.floatingPetEnableLabel"))
    }

    private static let popoverSource: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/PokeDexBar/UI/PopoverView.swift")
    }()
}
