import Foundation

/// 오늘의 목표 — 세기·진행 판정·수령.
extension PlayerStore {
    struct DailyQuestStatus: Identifiable, Equatable {
        let quest: DailyQuest.Quest
        let done: Int
        let claimed: Bool
        var id: String { quest.id }
        var target: Int { quest.target }
        var achieved: Bool { done >= quest.target }
        var claimable: Bool { achieved && !claimed }
    }

    /// 오늘의 셋. 저장된 값이 아니라 날짜와 시드에서 매번 다시 나온다.
    var dailyQuests: [DailyQuest.Quest] {
        DailyQuest.roll(date: state.lastDate, seed: state.offerSeed)
    }

    func dailyQuestStatuses() -> [DailyQuestStatus] {
        dailyQuests.map { quest in
            DailyQuestStatus(quest: quest,
                             done: state.dailyCounts[quest.kind.rawValue] ?? 0,
                             claimed: state.claimedDailyQuests.contains(quest.id))
        }
    }

    /// 오늘의 활동 하나를 센다. **호출부는 그 일이 실제로 일어난 뒤에만 부른다** — 거절된
    /// 뽑기·부화까지 세면 목표가 저절로 차오른다.
    func countDailyActivity(_ kind: DailyQuest.Kind, by amount: Int = 1) {
        guard amount > 0 else { return }
        mutate { $0.dailyCounts[kind.rawValue, default: 0] += amount }
    }

    @discardableResult
    func claimDailyQuest(_ quest: DailyQuest.Quest) -> Bool {
        guard let status = dailyQuestStatuses().first(where: { $0.id == quest.id }),
              status.claimable else { return false }
        mutate {
            // 포인트에는 상한이 있다 — 봉인이 깨진 세이브의 큰 값이 이후 덧셈에서 오버플로
            // 트랩을 내는 것을 경계 한 곳에서 막는다(`ReleaseBalance.maxPoints` 와 같은 이유).
            $0.researchPoints = min(ReleaseBalance.maxPoints,
                                    $0.researchPoints + DailyQuest.points(for: quest))
            $0.claimedDailyQuests.insert(quest.id)
        }
        return true
    }

    /// 셋을 다 받았나 — 덤의 조건은 *달성*이 아니라 *수령*이다. 안 그러면 하나도 안 누르고
    /// 덤만 가져가는 길이 생긴다.
    var dailyBonusReady: Bool {
        !state.claimedDailyBonus
            && !dailyQuests.isEmpty
            && dailyQuests.allSatisfy { state.claimedDailyQuests.contains($0.id) }
    }

    @discardableResult
    func claimDailyBonus() -> Bool {
        guard dailyBonusReady else { return false }
        mutate { s in
            grant([DailyQuest.completionBonus], into: &s)
            s.claimedDailyBonus = true
        }
        return true
    }
}
