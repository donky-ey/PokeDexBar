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

    /// 버튼 문구. **값이 여기 붙는다** — 각주에 두었더니 "이번에 얼마 내는지 모르겠다"가 됐다
    /// (사용자 지적). 값이 모자라도 계속 보인다 — 얼마가 필요한지 알아야 기다릴 수 있다.
    static func buttonTitle(store: PlayerStore) -> String {
        let l = store.l
        guard let price = store.nextItemDrawPrice else { return l.itemDrawButton }
        return price == 0 ? l.itemDrawButtonFree : l.itemDrawButtonPriced(price)
    }

    /// 줄 아래 한 줄. 누를 수 있으면 **사다리를 미리** 말하고(연타하다 값이 네 배가 된 것을 뒤늦게
    /// 아는 일을 막는다), 못 누르면 **왜 못 누르는지**가 온다 — 회색 버튼만 두면 물어볼 곳이 없다.
    static func footnote(store: PlayerStore) -> String {
        let l = store.l
        guard let price = store.nextItemDrawPrice else { return l.itemDrawSoldOut }
        guard store.state.researchPoints >= price else { return l.itemDrawNeedsPoints(price) }
        // 다음 값이 없다면(상한) 사다리를 말할 것이 없으므로 지금 상태만 말한다.
        guard let next = store.itemDrawPriceAfterNext else { return l.itemDrawSoldOut }
        return l.itemDrawLadder(next)
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
            // 확률이 버튼 **위**에 선다 — 무엇이 들어 있는지 보고 나서 누르게. 아래에 두면
            // 누른 뒤에야 읽는다. 품목 이름이 곧 "무슨 기능인가"의 답이다(사용자 지적).
            Text(ItemDrawBalance.oddsText(store.language))
                .font(.system(size: 8)).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            Button(Self.buttonTitle(store: store)) {
                if let result = store.drawItem() { reveal = result }
            }
            .buttonStyle(.bordered).controlSize(.small)
            .disabled(!store.canDrawItem)
            Text(Self.footnote(store: store))
                .font(.system(size: 8)).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
