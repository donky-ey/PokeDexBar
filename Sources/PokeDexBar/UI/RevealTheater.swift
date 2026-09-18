import SwiftUI

/// 한 박자의 상태 — 가운데 그림이 이걸 받아 자기 움직임을 만든다.
struct RevealBeat {
    let stage: RevealStage
    /// 매 단계 움츠릴 때 오른다 — `KeyframeAnimator` 의 방아쇠.
    let beat: Int
    /// 링·파티클이 터지는 순간.
    let burst: Bool
    /// 마지막 단계에서 한 번 오른다 — 이로치 반짝임처럼 끝에 한 번만 터뜨릴 것의 방아쇠.
    let finale: Int
}

/// 뽑기 연출의 **무대**. 배경·링·파티클·단계 진행이 여기 살고, 가운데에 서는 그림과 결과 줄만
/// 주입받는다. 알과 아이템이 같은 무대를 쓰는 이유는 갈라 두면 한쪽만 고쳐지기 때문이다.
///
/// 이름이 `RevealStage` 가 아닌 이유: 그 이름은 이미 `EggReveal.stages(for:)` 가 돌려주는
/// **한 단계**를 가리킨다. 같은 이름을 무대 전체에도 붙이면 둘이 섞인다.
struct RevealTheater<Center: View, Result: View>: View {
    let grade: Grade
    let onDone: () -> Void
    @ViewBuilder let center: (RevealBeat) -> Center
    @ViewBuilder let result: (RevealStage) -> Result

    @State private var stageIndex = 0
    @State private var beat = 0
    @State private var burst = false
    @State private var finale = 0
    @State private var showResult = false

    private var stages: [RevealStage] { EggReveal.stages(for: grade) }
    private var stage: RevealStage { stages[min(stageIndex, stages.count - 1)] }

    var body: some View {
        ZStack {
            // **뒤가 비치면 안 된다.** 아래 그라데이션은 가운데가 16% 밖에 안 가려서, 이 연출이
            // 부화칸 줄 위에 뜨면 방금 놓인 알의 등급색과 라벨이 그대로 보였다(사용자 지적) —
            // 연출이 끝나기 전에 결과를 알게 된다. 불투명한 바닥을 깔아 무대의 느낌은 그대로
            // 두고 새는 것만 막는다. `DrawRevealCoverTests` 가 이것을 픽셀로 잠근다.
            Color.black.ignoresSafeArea()
            // 가운데로 시선을 모으는 어둠 — 평평한 검정보다 무대처럼 읽힌다.
            RadialGradient(colors: [stage.color.opacity(0.16), .black.opacity(0.93)],
                           center: .center, startRadius: 0, endRadius: 190)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                ZStack {
                    rings
                    particles
                    center(RevealBeat(stage: stage, beat: beat, burst: burst, finale: finale))
                }
                .frame(width: 150, height: 150)
                if showResult {
                    result(stage).transition(.opacity.combined(with: .offset(y: 8)))
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onDone() }   // 기다리기 싫으면 눌러서 건너뛴다
        .task { await run() }
    }

    /// 충격파 링 — 작은 판에서는 파티클보다 이쪽이 훨씬 잘 읽힌다. 둘을 어긋나게 띄운다.
    private var rings: some View {
        ForEach(0..<RevealMotion.ringCount, id: \.self) { index in
            Circle()
                .strokeBorder(stage.color, lineWidth: burst ? 1 : 3)
                .frame(width: 74, height: 74)
                .scaleEffect(burst ? RevealMotion.ringMaxScale : 0.35)
                .opacity(burst ? 0 : 0.85)
                .animation(.easeOut(duration: RevealMotion.burstDecay)
                    .delay(RevealMotion.ringDelay(index)), value: burst)
        }
    }

    /// 바깥으로 뻗는 짧은 획 — 동그라미보다 방향과 속도가 보인다.
    private var particles: some View {
        ForEach(0..<RevealMotion.particleCount, id: \.self) { index in
            let offset = RevealMotion.particleOffset(index: index,
                                                     count: RevealMotion.particleCount,
                                                     radius: RevealMotion.particleRadius)
            Capsule()
                .fill(stage.color)
                .frame(width: RevealMotion.particleLength(index: index),
                       height: stage.sparkles && index.isMultiple(of: 3) ? 4 : 3)
                .rotationEffect(.degrees(RevealMotion.particleAngle(index: index)))
                .offset(x: burst ? offset.width : 0, y: burst ? offset.height : 0)
                .opacity(burst ? 0 : 1)
                .animation(.easeOut(duration: RevealMotion.burstDecay), value: burst)
        }
    }

    /// 단계를 하나씩 지나간다. 각 단계는 예비동작이 끝나는 시점에 터진다 —
    /// 그래야 "움츠렸다가 터졌다"로 읽히고, 동시에 터지면 그냥 깜빡임이 된다.
    private func run() async {
        for index in stages.indices {
            stageIndex = index
            burst = false
            beat += 1
            try? await Task.sleep(for: .seconds(RevealMotion.anticipation))
            if Task.isCancelled { return }
            burst = true
            if index == stages.count - 1 {
                withAnimation(.easeOut(duration: 0.28).delay(0.18)) { showResult = true }
                finale += 1
            }
            let rest = EggReveal.duration(stageIndex: index, of: stages.count)
                - RevealMotion.anticipation
            try? await Task.sleep(for: .seconds(rest))
            if Task.isCancelled { return }
        }
        onDone()
    }
}
