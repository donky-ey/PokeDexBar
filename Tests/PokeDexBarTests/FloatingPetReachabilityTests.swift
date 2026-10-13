import XCTest
@testable import PokeDexBar

/// 플로팅 펫이 **실제로 손에 닿는 자리인가.**
///
/// 사용자 제보: 펫이 어느 순간 사라졌고, 껐다 켜도·재설치해도 안 돌아온다. 위치는 `UserDefaults`
/// 라 재설치로 안 지워지고, 복원 가드는 "화면과 1pt 라도 겹치면 통과"였다 — 그래서 가장자리에
/// 한 줄만 걸친 자리가 켤 때마다 그대로 복원됐다. 완전히 화면 밖이면 오히려 가드가 잡아 기본
/// 자리로 돌렸으니, **조금 걸친 경우만** 영원히 갇힌 것이다.
final class FloatingPetReachabilityTests: XCTestCase {
    private let screen = NSRect(x: 0, y: 0, width: 1440, height: 875)
    private let size: CGFloat = 96

    private func pet(at origin: NSPoint) -> NSRect {
        NSRect(origin: origin, size: NSSize(width: size, height: size))
    }

    func testAPetFullyOnScreenIsReachable() {
        XCTAssertTrue(FloatingPetController.isReachable(pet(at: NSPoint(x: 600, y: 400)),
                                                        visibleFrames: [screen]))
    }

    /// **이 결함의 정체.** 오른쪽 끝에 1pt 만 걸친 펫 — 예전 가드는 겹친다고 통과시켰다.
    func testASliverAtTheEdgeIsNotReachable() {
        let sliver = pet(at: NSPoint(x: screen.maxX - 1, y: 400))
        XCTAssertTrue(screen.intersects(sliver), "전제: 화면과 겹치긴 한다(예전 가드가 통과시킨 모양)")
        XCTAssertFalse(FloatingPetController.isReachable(sliver, visibleFrames: [screen]),
                       "한 줄만 보이는 펫을 손에 닿는다고 봤다")
    }

    /// 네 가장자리 어디로 밀려나도 같다 — 한 방향만 고치면 나머지 셋에서 또 갇힌다.
    func testASliverOnAnyEdgeIsNotReachable() {
        let slivers = [
            pet(at: NSPoint(x: screen.maxX - 1, y: 400)),            // 오른쪽
            pet(at: NSPoint(x: screen.minX - size + 1, y: 400)),     // 왼쪽
            pet(at: NSPoint(x: 600, y: screen.maxY - 1)),            // 위
            pet(at: NSPoint(x: 600, y: screen.minY - size + 1)),     // 아래
        ]
        for sliver in slivers {
            XCTAssertFalse(FloatingPetController.isReachable(sliver, visibleFrames: [screen]),
                           "\(sliver.origin) 에서 갇힌다")
        }
    }

    /// 대조군 — 가장자리에 **반쯤** 걸친 펫은 잡을 수 있다. 이것까지 막으면 사용자가 일부러
    /// 구석에 붙여 둔 자리를 매번 빼앗는다.
    func testAPetHalfOverTheEdgeIsStillReachable() {
        let half = pet(at: NSPoint(x: screen.maxX - size / 2 - 4, y: 400))
        XCTAssertTrue(FloatingPetController.isReachable(half, visibleFrames: [screen]))
    }

    func testAPetOnNoScreenIsNotReachable() {
        XCTAssertFalse(FloatingPetController.isReachable(pet(at: NSPoint(x: 5000, y: 5000)),
                                                         visibleFrames: [screen]))
    }

    /// 화면이 여럿이면 그중 하나에서 잡히면 된다 — 외장 모니터에 둔 펫이 기본 자리로 끌려오면 안 된다.
    func testAPetOnASecondScreenIsReachable() {
        let external = NSRect(x: 1440, y: 0, width: 1920, height: 1080)
        XCTAssertTrue(FloatingPetController.isReachable(pet(at: NSPoint(x: 2000, y: 500)),
                                                        visibleFrames: [screen, external]))
    }

    /// 크기가 0 이 되면 어디에 있든 안 보인다 — 다른 경로로 같은 증상이 나는 구멍이다.
    func testAZeroSizedPetIsNeverReachable() {
        let zero = NSRect(x: 600, y: 400, width: 0, height: 0)
        XCTAssertFalse(FloatingPetController.isReachable(zero, visibleFrames: [screen]))
    }
}
