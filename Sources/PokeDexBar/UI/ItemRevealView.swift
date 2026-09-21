import SwiftUI

/// 박사의 상자 결과 연출 — 알 뽑기와 **같은 무대**(`RevealTheater`)를 쓰고, 가운데 그림과
/// 결과 줄만 아이템의 것으로 바꾼다.
struct ItemRevealView: View {
    let result: ItemDrawResult
    let l: L
    let language: AppLanguage
    let onDone: () -> Void


    var body: some View {
        RevealTheater(grade: result.rarity, onDone: onDone) { moment in
            glyph(moment)
        } result: { stage in
            VStack(spacing: 3) {
                Text(result.count > 1
                     ? "\(result.item.label(language)) \(l.itemDrawCount(result.count))"
                     : result.item.label(language))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(stage.color)
                    .multilineTextAlignment(.center)
                Text(l.itemDrawLanded).font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }

    /// 가운데 그림 — `ItemIcon` 하나가 품목을 보고 정한다. 예전에는 여기서 SF Symbol 을 골랐는데
    /// (약통이 경험치 사탕, 반짝이는 손이 마사지 쿠폰), 손으로 그린 알 그림 옆에 시스템 글리프가
    /// 서니 따로 놀았다(사용자 지적). 그릴 것의 선택은 `ItemIcon.drawing(for:)` 한 곳에만 있다.
    private func glyph(_ moment: RevealBeat) -> some View {
        ItemIcon(item: result.item, size: 78)
            .scaleEffect(moment.burst ? 1.12 : 0.94)
            .shadow(color: moment.stage.color.opacity(0.85), radius: moment.burst ? 22 : 8)
            .animation(.spring(duration: 0.3), value: moment.beat)
    }
}
