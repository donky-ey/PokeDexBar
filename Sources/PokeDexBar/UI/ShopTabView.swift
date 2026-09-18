import SwiftUI

/// 상점 — 알 뽑기, 슬롯 확장, 아이템. 확률은 그대로 적어 둔다.
struct ShopTabView: View {
    let store: PlayerStore
    let provider: any PokeProviding
    /// 종 번호 → 진화 라인. "박사의 제안" 카드가 이름을 보여주려면 필요하다 — 박스·부화 슬롯과
    /// 같은 방식으로 위에서 받아 내려보낸다(`ProfessorOfferSection` 참고).
    var lines: [Int: EvoLine] = [:]
    var onNeedLine: (Int) -> Void = { _ in }

    /// 뽑기 작업을 뷰 생애에 묶는다 — 안 그러면 팝오버가 닫혔다 다시 열려 새 뷰가 생겨도
    /// 이전 네트워크 조회가 백그라운드에서 계속 돌아 뒤늦게 착지할 수 있다(스타터 픽커와 동일 문제).
    private var l: L { store.l }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                walletRow
                ProfessorOfferSection(store: store, provider: provider, lines: lines,
                                      onNeedLine: onNeedLine)
                // 의뢰는 **박사 바로 아래**에 붙인다(사용자 결정). 보상이 박사 포인트인데 그
                // 포인트를 쓰는 자리가 바로 위라, 벌고 쓰는 순환이 한 화면에서 닫힌다 — 홈에
                // 뒀을 땐 보상과 쓰임새가 탭 하나를 사이에 두고 떨어져 있었다.
                DailyGoalsView(store: store)
                // 포인트를 주는 곳(제안·의뢰) 바로 아래가 쓰는 곳이다.
                ProfessorBoxSection(store: store)
                Divider()
                slotSection
                // 목록은 `ShopCategory` 가 정한다 — 뷰가 칸을 나열하면 새 분류가 조용히 빠진다.
                ForEach(ShopCategory.allCases, id: \.self) { categorySection($0) }
            }
            .padding(.vertical, 2)
        }
        .frame(height: 320)
        // 연출은 상점 위에만 덮인다 — 팝오버 전체를 가리면 탭 전환이 막힌다.
        .overlay {
        }
        .onDisappear {
            // 팝오버가 닫혀 뷰가 사라지면 진행 중인 뽑기 조회도 함께 끊는다 — 살려두면
            // 다음에 연 새 뷰의 뽑기와 경합해 조용히 지는 쪽이 생긴다.
        }
    }

    private var walletRow: some View {
        HStack {
            Text(l.shopWallet).font(.system(size: 10)).foregroundStyle(.secondary)
            Spacer()
            Text(TokenFormatter.compact(store.state.wallet))
                .font(.system(size: 13, weight: .bold)).monospacedDigit()
        }
    }


    private var slotSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(l.shopSlotSection).font(.system(size: 12, weight: .semibold))
            if let price = store.nextSlotPrice {
                HStack {
                    Text(l.shopSlotUpgrade(store.state.slots, store.state.slots + 1))
                        .font(.system(size: 10))
                    Spacer()
                    Button(TokenFormatter.compact(price)) { _ = store.buySlot() }
                        .buttonStyle(.bordered).controlSize(.small)
                        .disabled(store.state.wallet < price)
                }
            } else {
                Text(l.shopSlotsMaxed)
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
            }
        }
    }

    /// 한 분류의 품목들. 목록은 `ShopItem.category` 가 정한다 — 뷰가 품목 이름을 나열하면
    /// 새 품목이 조용히 안 팔리는 일이 생긴다.
    private func categorySection(_ category: ShopCategory) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(category.title(store.language)).font(.system(size: 12, weight: .semibold))
            ForEach(ShopItem.allCases.filter { $0.category == category && $0.isSold },
                    id: \.self) { item in
                itemRow(item)
            }
        }
    }

    private func itemRow(_ item: ShopItem) -> some View {
        // 사다리 부적은 "산다/샀다" 가 아니라 **지금 몇 단계인가**로 말한다 — 다음 단계 값과
        // 지금 배율을 같이 보여야 "한 번 더 올릴까" 를 판단할 수 있다.
        if CharmLadder.isTiered(item) { return AnyView(charmRow(item)) }
        let owned = item.isCharm ? (store.owns(item) ? 1 : 0) : store.count(of: item)
        let soldOut = item.isCharm && store.owns(item)
        return AnyView(HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(item.label(store.language)).font(.system(size: 11, weight: .medium))
                    if owned > 0 {
                        Text(item.isConsumable ? "×\(owned)" : l.shopItemOwned)
                            .font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                }
                Text(item.detail(store.language)).font(.system(size: 9)).foregroundStyle(.tertiary)
            }
            Spacer()
            Button(soldOut ? l.shopItemOwnedButton : TokenFormatter.compact(item.price)) { _ = store.buy(item) }
                .buttonStyle(.bordered).controlSize(.small)
                .disabled(soldOut || store.state.wallet < item.price)
        })
    }

    private func charmRow(_ item: ShopItem) -> some View { CharmShopRow(store: store, item: item) }

}

/// 단계가 있는 부적 한 줄 — 지금 단계·지금 효과, 그리고 다음 단계 값.
///
/// 상점 뷰에서 떼어 둔 이유: 이 줄 하나가 사다리의 전부라, 릴리스 그림도 **이 줄을 그대로**
/// 써야 한다(손으로 그린 목업이 앱과 어긋나 README 에 몇 달 남았던 전례 — CLAUDE.md §릴리스).
struct CharmShopRow: View {
    let store: PlayerStore
    let item: ShopItem

    private var l: L { store.l }

    var body: some View {
        let tier = store.charmTier(item)
        let next = store.nextCharmPrice(item)
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(item.label(store.language)).font(.system(size: 11, weight: .medium))
                    if tier > 0 {
                        Text(l.charmTierBadge(tier))
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.22), in: Capsule())
                    }
                }
                Text(l.charmShopEffect(item, tier: tier))
                    .font(.system(size: 9)).foregroundStyle(.tertiary)
            }
            Spacer()
            Button(next.map(TokenFormatter.compact) ?? l.charmMaxTier) {
                _ = store.upgradeCharm(item)
            }
            .buttonStyle(.bordered).controlSize(.small)
            .disabled(!store.canUpgradeCharm(item))
        }
    }
}
