import SwiftUI

/// 박사의 상자 — 박사 포인트로 도는 아이템 뽑기. 제안·의뢰 아래 세 번째 칸이다.
/// 포인트를 주는 곳과 쓰는 곳이 한 구역에 모여 있어야 포인트가 무엇인지 읽힌다.
struct ProfessorBoxSection: View {
    let store: PlayerStore
    @State private var reveal: ItemDrawResult?

    private var l: L { store.l }

    /// 줄 아래 한 줄. 못 누를 때는 **왜 못 누르는지**가 온다 — 회색 버튼만 두면 물어볼 곳이 없다.
    static func footnote(store: PlayerStore) -> String {
        let l = store.l
        guard let price = store.nextItemDrawPrice else { return l.itemDrawSoldOut }
        if store.itemDrawIsFree { return l.itemDrawFreeToday }
        return store.state.researchPoints >= price
            ? l.itemDrawPrice(price) : l.itemDrawNeedsPoints(price)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                ProfessorIcon(size: 14)
                Text(l.professorBoxTitle).font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(l.researchPoints(store.state.researchPoints))
                    .font(.system(size: 9, weight: .medium)).monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Button(l.itemDrawButton) {
                if let result = store.drawItem() { reveal = result }
            }
            .buttonStyle(.bordered).controlSize(.small)
            .disabled(!store.canDrawItem)
            Text(Self.footnote(store: store))
                .font(.system(size: 8)).foregroundStyle(.tertiary)
        }
        .overlay {
            if let reveal {
                ItemRevealView(result: reveal, l: l, language: store.language) {
                    self.reveal = nil
                }
            }
        }
    }
}
