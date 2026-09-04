import Foundation

/// 오늘의 목표 — 하루치 작은 과제 셋.
///
/// **미션·컬렉션과 셋이 다른 것을 센다.** 도감 미션은 *얼마나 모았나*(숫자), 컬렉션은
/// *무엇을 모았나*(이야기), 이쪽은 *오늘 무엇을 했나*(활동)다. 셋을 한 목록에 섞으면
/// 영영 안 끝나는 것과 오늘 끝나는 것이 같은 줄에 서게 된다.
///
/// **굴린 결과를 저장하지 않는다.** 날짜와 세이브 시드만 있으면 언제든 같은 셋이 다시 나오므로
/// (`roll`), 상태로 남길 것은 *오늘 얼마나 했나*와 *무엇을 받았나*뿐이다.
enum DailyQuest {
    /// 셀 수 있는 활동. `rawValue` 가 곧 오늘치 계수기의 키다.
    enum Kind: String, Codable, Sendable, CaseIterable {
        case drawEggs, hatchEggs, evolve, useCandy, sendToProfessor, openOffer
    }

    struct Quest: Equatable, Sendable, Identifiable {
        let kind: Kind
        let target: Int
        var id: String { "\(kind.rawValue)-\(target)" }
    }

    /// 하루에 내미는 개수 — 박사의 제안과 같은 셋.
    static let dailyCount = 3

    /// 후보 — 종류마다 난도 한 단계씩. 같은 종류가 하루에 둘 나오지 않게 `roll` 이 종류로 고른다.
    static let pool: [Quest] = Kind.allCases.flatMap { kind in
        targets(for: kind).map { Quest(kind: kind, target: $0) }
    }

    /// 그 활동의 하루 목표치 후보.
    ///
    /// **하루에 실제로 닿을 수 있는 값이어야 한다.** 알 뽑기는 1천만 토큰이라 다섯 번도 가볍지만,
    /// 진화는 조건이 걸려 있어 한 번도 큰일이다 — 그래서 종류마다 자릿수가 다르다.
    static func targets(for kind: Kind) -> [Int] {
        switch kind {
        case .drawEggs: [1, 3, 5]
        case .hatchEggs: [1, 2, 3]
        case .evolve: [1]   // 조건에 걸린 종류 — `conditionGated` 참고
        // 사탕은 **한 개까지**. 세 개는 상점가로 1.5B 인데 보상은 10P 라, 알 뽑기 다섯 번
        // (50M · 15P)과 서른 배가 벌어졌다(사용자 지적). 목표가 아니라 세금이 된다.
        case .useCandy: [1]
        case .sendToProfessor: [1, 3]
        case .openOffer: [1, 3]
        }
    }

    /// 이 목표를 채우는 데 **드는 토큰**. 안 드는 것(부화·진화·보내기·제안 열기)은 0 이다.
    ///
    /// 후보를 만들 때 이 질문을 안 했던 것이 결함의 정체였다 — "사탕 3개"가 1.5B 를 태우면서
    /// 알 뽑기 다섯 번(50M)과 같은 자리에 서 있었다. 값이 코드에 있어야 테스트가 물어볼 수 있다.
    static func tokenCost(for quest: Quest) -> Int {
        switch quest.kind {
        case .drawEggs: quest.target * EggBalance.drawPrice
        case .useCandy: quest.target * ShopItem.expCandy.price
        case .hatchEggs, .evolve, .sendToProfessor, .openOffer: 0
        }
    }

    /// **오늘 하고 싶어도 못 할 수 있는 종류.** 진화는 레벨·도구·친밀도가 걸려 있어, 오늘
    /// 진화 가능한 개체가 아예 없는 날이 흔하다 — 그런 종류에 둘 이상을 요구하면 어려운 게
    /// 아니라 불가능해지고, 셋 중 하나가 불가능하면 그날의 덤까지 같이 닫힌다.
    ///
    /// 나머지는 마음먹으면 오늘 안에 할 수 있다: 뽑기는 지갑만 되면 되고, 부화는 뽑으면 따라오고,
    /// 보내기는 박스에 여분만 있으면 되고, 제안은 박사가 **매일** 셋을 내민다.
    static let conditionGated: Set<Kind> = [.evolve]

    /// 하루짜리 목표가 요구해도 되는 지출의 상한 — **하루 수입 한 벌**(실사용 관찰 500M/일).
    /// 이보다 크면 그날 번 것을 통째로 넣고도 모자라, 목표가 아니라 손해가 된다.
    static let maxSpend = 500_000_000

    /// 이 과제의 보상 — **박사 포인트**.
    ///
    /// 사탕이 아닌 이유: 하루 셋이면 상점가로 1.5B 어치가 매일 나오는데, 그건 이 앱의 하루 수입을
    /// 몇 배로 넘긴다(실사용 500M/일 기준). 포인트는 토큰과 벽이 쳐져 있어(포인트로 알을 못 사고
    /// 토큰으로 박사와 거래를 못 한다) 경제를 안 건드리면서, 자릿수가 딱 맞는다 — 커먼 한 마리를
    /// 보내면 2P, 커먼 제안을 데려오는 값이 10P 다.
    static func points(for quest: Quest) -> Int {
        let index = targets(for: quest.kind).firstIndex(of: quest.target) ?? 0
        return 5 + index * 5   // 5 · 10 · 15
    }

    /// 셋을 다 끝낸 날의 덤(사용자 결정 — "둘 섞기"). 하루 한 번뿐이라 사탕이어도 경제가 안 밀린다.
    static let completionBonus: DexMissionReward = .item(.expCandy, 1)

    /// 오늘의 셋. **날짜와 사람, 둘 다 굴림에 들어간다** — 날짜만 넣으면 같은 날 지구상 모든
    /// 설치가 같은 과제를 받는다(박사의 제안이 실제로 그렇게 나갔다).
    ///
    /// 종류가 겹치지 않게 고른다: "알 3개 뽑기"와 "알 5개 뽑기"가 같이 서면 둘이 사실상 한 줄이다.
    static func roll(date: String, seed: UInt64) -> [Quest] {
        var kinds = Kind.allCases
        var picked: [Quest] = []
        for slot in 0..<min(dailyCount, kinds.count) {
            let kindRoll = unit(date: date, seed: seed, slot: slot, salt: "kind")
            let kind = kinds.remove(at: Int(kindRoll * Double(kinds.count)) % kinds.count)
            let options = targets(for: kind)
            let targetRoll = unit(date: date, seed: seed, slot: slot, salt: "target")
            let target = options[Int(targetRoll * Double(options.count)) % options.count]
            picked.append(Quest(kind: kind, target: target))
        }
        return picked
    }

    /// 0…1. 날짜·사람·자리·용도 네 축을 전부 섞는다(FNV-1a 64 — `BattleStateForm.stintUnit` 과 같은 관례).
    private static func unit(date: String, seed: UInt64, slot: Int, salt: String) -> Double {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        func mix(_ byte: UInt8) {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        date.utf8.forEach(mix)
        salt.utf8.forEach(mix)
        withUnsafeBytes(of: seed) { $0.forEach(mix) }
        withUnsafeBytes(of: UInt64(slot)) { $0.forEach(mix) }
        return Double(hash % 1_000_000) / 1_000_000
    }
}
