import AppKit
import SwiftUI
import XCTest
@testable import PokeDexBar

/// Used for the optional keyboard-focus check on an interactive desktop.
private final class SessionKeyTestWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

/// #275: 만료 안내에서 설정으로 들어오면 고급 섹션이 펼쳐지고 세션 키 입력란이 뷰포트 안에
/// 보여야 한다 — 접힌 disclosure 안에 숨어 있으면 안내가 막다른 길이 된다.
/// (포크: CompanionStore·난이도 슬라이더 단언은 업스트림 전용이라 기존 슬라이더 보존으로 치환.)
@MainActor
final class SessionKeySettingsRenderingTests: XCTestCase {
    func testSessionKeyEntryOpensInsideViewportAndPreservesExistingControls() async throws {
        let suite = "SessionKeySettingsRendering-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(suite).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let usage = UsageStore(providers: [], autoRefresh: false, defaults: defaults)
        let player = PlayerStore(fileURL: file, rng: SeededRNG(seed: 1))
        let navigation = PopoverNavigation()
        navigation.openSessionKeySettings()
        let host = NSHostingController(rootView: SettingsView(
            onClose: {}, startExpanded: navigation.expandAdvancedOnOpen)
            .environment(usage).environment(player).environment(UpdateChecker())
            .frame(width: PopoverMetrics.width))
        let previousKeyWindow = NSApp.keyWindow
        let window = SessionKeyTestWindow(
            contentRect: NSRect(x: -10000, y: -10000, width: PopoverMetrics.width, height: 460),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentViewController = host
        window.makeKeyAndOrderFront(nil)
        defer {
            window.orderOut(nil)
            previousKeyWindow?.makeKey()
        }
        host.view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(500))
        host.view.layoutSubtreeIfNeeded()
        let views = descendants(of: host.view)
        let secure = try XCTUnwrap(views.compactMap { $0 as? NSSecureTextField }.first)
        let rect = secure.convert(secure.bounds, to: host.view)
        XCTAssertTrue(host.view.bounds.contains(rect), "session key entry must be visible after scrolling")
        // Hosted CI renders the layout but does not grant this XCTest window an editor.
        // Verify keyboard focus on an interactive Mac with PTB_VERIFY_KEYBOARD_FOCUS=1.
        if ProcessInfo.processInfo.environment["PTB_VERIFY_KEYBOARD_FOCUS"] == "1" {
            XCTAssertNotNil(secure.currentEditor(), "session key entry must receive keyboard focus")
            XCTAssertTrue(secure.currentEditor() === window.firstResponder)
        }
        // 기존 설정 컨트롤(경고/위험 임계 슬라이더 2개 — 펫 크기 슬라이더는 펫이 꺼진 기본값에선
        // 렌더되지 않는다)이 세션 키 섹션 병합 후에도 살아 있어야 한다.
        XCTAssertGreaterThanOrEqual(views.compactMap { $0 as? NSSlider }.count, 2,
                                    "existing sliders must survive the Settings merge")
        XCTAssertTrue(navigation.showSettings)
        navigation.reset()
        XCTAssertFalse(navigation.expandAdvancedOnOpen)
    }

    private func descendants(of view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { descendants(of: $0) }
    }
}
