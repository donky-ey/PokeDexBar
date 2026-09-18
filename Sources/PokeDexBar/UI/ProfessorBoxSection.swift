import SwiftUI

/// 박사의 상자 — 박사 포인트로 도는 아이템 뽑기. 제안·의뢰 아래 세 번째 칸이다.
/// 포인트를 주는 곳과 쓰는 곳이 한 구역에 모여 있어야 포인트가 무엇인지 읽힌다.
struct ProfessorBoxSection: View {
    let store: PlayerStore
    /// 연출 상태는 여기서 갖지 않는다 — `ShopTabView` 가 갖고 있다가 자기 탭 프레임(320pt) 위에
    /// 띄운다. 이 구역 자체는 52pt 남짓이라, 여기서 `.overlay` 로 직접 띄우면 `RevealTheater`
    /// 무대(150pt + 결과줄)가 이 자리보다 커서 뒤 목록이 비친다(딥리뷰 지적, v1.16.2 의 알 뽑기
    /// 회귀와 같은 부류) — `ShopTabView.swift` 의 `.overlay` 참고.
    @Binding var reveal: ItemDrawResult?

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
    }
}
