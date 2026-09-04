import SwiftUI

/// 오늘의 목표 — 홈 탭. 하루면 사라지는 과제 셋과, 셋을 다 받은 날의 덤.
///
/// **홈에 있는 이유**(사용자 판단): 처음엔 도감 탭의 미션 위에 뒀는데, 도감은 "무엇을 모았나"를
/// 보는 화면이라 오늘 할 일과 아무 상관이 없고 자주 열지도 않는다 — 하루면 사라질 것을 거기 두면
/// 있는 줄도 모르고 지나간다. 목표가 가리키는 행동(뽑기·부화·진화)도 홈과 상점 쪽 일이다.
///
/// 팝오버에서 떼어 둔 이유는 `DayCareSlotsView` 와 같다: 이 줄만 따로 오프스크린 렌더해
/// 릴리스 그림으로 쓸 수 있어야 하고, 펼침 상태가 홈 전체의 상태와 안 섞인다.
struct DailyGoalsView: View {
    let store: PlayerStore
    /// 기본으로 펼쳐 둔다 — 하루면 사라질 것을 접어 두면 있는 줄도 모른다.
    @State private var expanded = true

    var body: some View { section }


    
    /// 오늘의 목표 — **미션 위에 둔다.** 도감 미션은 몇 달이 걸리는 사다리고 이쪽은 오늘 끝나는
    /// 일이라, 아래에 두면 오늘 할 수 있는 것이 스크롤 밖으로 밀린다. 기본으로 펼쳐 두는 이유도
    /// 같다 — 하루면 사라질 것을 접어 두면 있는 줄도 모른다.
    @ViewBuilder
    private var section: some View {
        let statuses = store.dailyQuestStatuses()
        let claimable = statuses.count(where: \.claimable) + (store.dailyBonusReady ? 1 : 0)
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
                    Text(store.l.dailySection).font(.system(size: 10, weight: .semibold))
                    if claimable > 0 {
                        Text(store.l.missionClaimableBadge(claimable))
                            .font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.accentColor, in: Capsule())
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if expanded {
                ForEach(statuses) { status in row(status) }
                if store.dailyBonusReady { bonusRow }
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private func row(_ status: PlayerStore.DailyQuestStatus) -> some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(store.l.dailyQuestLabel(status.quest.kind, status.target))
                        .font(.system(size: 9, weight: .medium))
                    Text("\(min(status.done, status.target))/\(status.target)")
                        .font(.system(size: 8).monospacedDigit()).foregroundStyle(.secondary)
                    Text(store.l.dailyQuestReward(DailyQuest.points(for: status.quest)))
                        .font(.system(size: 8)).foregroundStyle(.tertiary)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.15))
                        Capsule().fill(status.claimable ? Color.accentColor : Color.secondary)
                            .frame(width: max(2, geo.size.width
                                * CGFloat(min(status.done, status.target)) / CGFloat(max(1, status.target))))
                    }
                }
                .frame(height: 3)
            }
            if status.claimed {
                Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            } else if status.claimable {
                Button(store.l.missionClaim) { store.claimDailyQuest(status.quest) }
                    .buttonStyle(.borderedProminent).controlSize(.small)
            }
        }
        .padding(.vertical, 1)
    }

    /// 셋을 다 받은 날의 덤 한 줄. **조건이 달성이 아니라 수령**이라, 위 셋을 다 누른 뒤에만 뜬다.
    private var bonusRow: some View {
        HStack(spacing: 6) {
            Text(store.l.dailyBonusLabel).font(.system(size: 9, weight: .medium))
            Spacer()
            Button(store.l.missionClaim) { store.claimDailyBonus() }
                .buttonStyle(.borderedProminent).controlSize(.small)
        }
        .padding(.vertical, 1)
    }}
