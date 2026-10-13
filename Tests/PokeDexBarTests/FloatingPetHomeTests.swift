import XCTest
@testable import PokeDexBar

/// 플로팅 펫을 처음 자리로 돌려보내기.
///
/// 원인(가장자리에 한 줄만 걸친 자리를 손에 닿는다고 본 가드)은 `FloatingPetReachabilityTests`
/// 가 잠근다. 이 버튼은 **원인과 무관하게** "내 펫 어디 갔지"를 한 번에 푸는 명시적 탈출구다 —
/// 다음에 또 다른 이유로 펫이 숨어도 사용자가 스스로 꺼낼 수 있어야 한다.
@MainActor
final class FloatingPetHomeTests: XCTestCase {

    /// 버튼은 **요청을 올리기만** 한다. 위치를 실제로 지우는 건 위치를 소유한 패널의 일이다 —
    /// 스토어가 위치 키 문자열을 알면 같은 리터럴이 두 곳에 생겨 드리프트가 난다.
    func testTheButtonRaisesARequest() {
        let defaults = UserDefaults(suiteName: "pet-home-\(UUID().uuidString)")!
        let store = UsageStore(defaults: defaults)
        let before = store.floatingPetHomeRequests
        store.sendFloatingPetHome()
        XCTAssertEqual(store.floatingPetHomeRequests, before + 1)
        store.sendFloatingPetHome()
        XCTAssertEqual(store.floatingPetHomeRequests, before + 2, "두 번째 요청이 안 잡힌다")
    }

    /// 지우기가 **두 키를 실제로** 없앤다. 하나만 지우면 다른 축이 남아 엉뚱한 자리로 간다.
    func testClearingRemovesBothSavedCoordinates() {
        let defaults = UserDefaults(suiteName: "pet-home-\(UUID().uuidString)")!
        defaults.set(1439.0, forKey: FloatingPetController.originXKey)
        defaults.set(-95.0, forKey: FloatingPetController.originYKey)

        FloatingPetController.clearSavedOrigin(in: defaults)
        XCTAssertNil(defaults.object(forKey: FloatingPetController.originXKey))
        XCTAssertNil(defaults.object(forKey: FloatingPetController.originYKey))
    }

    /// **돌려보내는 자리 자체가 손에 닿아야 한다.** 두 수정이 맞물리는 지점이다 — 기본 자리가
    /// 도달 가능성 가드에 걸리면 버튼을 눌러도 펫이 또 기본 자리로(=같은 곳으로) 튕겨 나가 안 보인다.
    func testTheHomePositionIsItselfReachable() {
        for frame in [NSRect(x: 0, y: 0, width: 1440, height: 875),
                      NSRect(x: 0, y: 25, width: 1280, height: 775),     // 메뉴바·독 뺀 작은 화면
                      NSRect(x: -1920, y: 0, width: 1920, height: 1055)] { // 왼쪽 보조 모니터가 주 화면
            for size in [UsageStore.floatingPetSizeRange.lowerBound,
                         UsageStore.floatingPetSizeRange.upperBound] {
                let origin = FloatingPetController.defaultPetOrigin(petSize: size, visibleFrame: frame)
                let pet = NSRect(origin: origin, size: NSSize(width: size, height: size))
                XCTAssertTrue(FloatingPetController.isReachable(pet, visibleFrames: [frame]),
                              "크기 \(size) 의 기본 자리가 \(frame) 에서 손에 안 닿는다")
            }
        }
    }

    /// 패널이 그 요청을 **관찰하고 있어야** 한다. 관찰 목록에서 빠지면 버튼을 눌러도 `sync()` 가
    /// 안 돌아 아무 일도 안 일어난다 — 컴파일도 되고 다른 테스트도 다 통과하는 조용한 고장이다.
    func testThePanelWatchesTheRequest() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/PokeDexBar/UI/FloatingPetPanel.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        let code = source.split(separator: "\n")
            .map { $0.contains("//") ? String($0[..<$0.range(of: "//")!.lowerBound]) : String($0) }
            .joined(separator: "\n")
        let observe = try XCTUnwrap(code.range(of: "private func observeSettings()"))
        let tracked = String(code[observe.upperBound...].prefix(500))
        XCTAssertTrue(tracked.contains("store.floatingPetHomeRequests"),
                      "패널이 「처음 자리로」 요청을 관찰하지 않는다 — 버튼이 아무 일도 안 한다")
    }

    /// 펫이 **꺼져 있을 때** 눌러도 위치가 지워져야 한다 — 그래야 다시 켤 때 제자리로 온다.
    /// 지우기가 `sync()` 의 숨김 분기 뒤에 있으면 꺼진 상태에서는 안 돈다(소스에서 순서를 본다).
    func testTheRequestIsHonouredEvenWhileThePetIsOff() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/PokeDexBar/UI/FloatingPetPanel.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        // 주석을 먼저 걷어낸다 — 통짜 검색은 바로 위 주석의 같은 낱말에 걸린다.
        let code = source.split(separator: "\n")
            .map { $0.contains("//") ? String($0[..<$0.range(of: "//")!.lowerBound]) : String($0) }
            .joined(separator: "\n")
        let sync = try XCTUnwrap(code.range(of: "private func sync()"))
        let body = String(code[sync.upperBound...].prefix(600))
        let clear = try XCTUnwrap(body.range(of: "clearSavedOrigin"), "sync 가 위치를 안 지운다")
        let hide = try XCTUnwrap(body.range(of: "hide()"))
        XCTAssertLessThan(clear.lowerBound, hide.lowerBound,
                          "지우기가 숨김 분기 뒤에 있어 펫이 꺼져 있을 때는 안 돈다")
    }
}
