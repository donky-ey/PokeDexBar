import Foundation

/// base 로 시작해 단계마다 두 배가 되는 값 사다리. 부적 단계와 아이템 뽑기가 공유한다.
///
/// **상한은 base 에서 유도한다.** 값이 두 배씩 뛰므로 단계가 커지면 `Int` 를 넘고, Swift 의
/// 곱셈은 트랩이라 프로세스가 죽는다. 부적에서 상한을 손으로 40 이라고 적었다가 실제로
/// 밟았다 — 2.5억 base 의 실제 한계는 35 였다. 상수로 두면 base 를 고칠 때 같이 안 움직인다.
struct DoublingLadder: Sendable {
    let base: Int
    /// 값과 누적이 모두 `Int` 안에 들어가는 가장 큰 단계.
    let maxStep: Int

    init(base: Int) {
        precondition(base > 0, "base must be positive")
        self.base = base
        var step = 1
        // 누적 `base × (2^t − 1)` 이 들어가는 가장 큰 t 를 센다.
        while step < 62 && Int.max / base >= (1 << (step + 1)) - 1 { step += 1 }
        self.maxStep = step
    }

    /// 이 단계를 사는 값. 1단계 미만이거나 상한 밖이면 값이 없다.
    func price(step: Int) -> Int? {
        guard step >= 1, step <= maxStep else { return nil }
        return base * (1 << (step - 1))
    }

    /// 여기까지 오는 데 든 총액 — 화면이 "지금까지 얼마 썼나" 를 보여줄 때 쓴다.
    func cumulative(through step: Int) -> Int {
        guard step >= 1 else { return 0 }
        return base * ((1 << min(step, maxStep)) - 1)
    }
}
