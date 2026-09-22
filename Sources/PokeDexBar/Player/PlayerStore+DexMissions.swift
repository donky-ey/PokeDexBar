import Foundation

/// 도감 미션 — 진행 판정과 수령.
extension PlayerStore {
    struct DexMissionStatus: Identifiable, Equatable {
        let mission: DexMission
        let done: Int
        let target: Int
        let claimed: Bool
        var id: String { mission.id }
        /// 달성했고 아직 안 받았다 — 화면이 "받기" 버튼을 이걸로 낸다.
        var claimable: Bool { !claimed && done >= target }
    }

    /// 전체 미션의 현재 상태. 순서는 카탈로그 그대로다.
    func dexMissionStatuses() -> [DexMissionStatus] {
        let dex = state.dex
        return DexMissions.all.map { mission in
            let progress = DexMissions.progress(of: mission, dex: dex)
            return DexMissionStatus(mission: mission, done: progress.done,
                                    target: progress.target,
                                    claimed: state.claimedDexMissions.contains(mission.id))
        }
    }

    /// 이 미션을 지금 받을 수 있나 — 달성했고 아직 안 받았으면 된다. **보상이 전부
    /// 아이템(확정권·사탕·부적)이라 다른 조건이 없다** — 알을 직접 주던 판에는 빈 부화
    /// 슬롯 요구가 여기 붙어 있었는데, 그게 "받기가 왜 안 되지" 를 만들었다(사용자 지적).
    func canClaimDexMission(_ mission: DexMission) -> Bool {
        !state.claimedDexMissions.contains(mission.id)
            && DexMissions.achieved(mission, dex: state.dex)
    }

    /// 받는다 — 보상이 전부 아이템이라 가방에 담고 끝이다. 알 확정권은 상점의 알 뽑기
    /// 자리에서 쓴다(`redeemEggTicket`).
    @discardableResult
    func claimDexMission(_ mission: DexMission) -> Bool {
        guard canClaimDexMission(mission) else { return false }
        mutate { s in
            grant(mission.rewards, into: &s)
            s.claimedDexMissions.insert(mission.id)
        }
        return true
    }

    /// 보상 묶음을 상태에 얹는다 — 미션과 컬렉션이 **같은 지급 경로**를 쓴다. 갈라 두면
    /// 한쪽만 고쳐지는 부류(두 화면이 각자 고르던 결함)가 여기서도 난다.
    /// 인스턴스 메서드인 이유: 포켓몬 지급이 시계(`obtainedAt`)와 굴림(성격·이로치)을 쓴다.
    func grant(_ rewards: [DexMissionReward], into s: inout PlayerState) {
        for reward in rewards {
            switch reward {
            case .eggTicket(let grade):
                if let ticket = ShopItem.eggTicket(for: grade) {
                    s.inventory[ticket.rawValue, default: 0] += 1
                }
            case .item(let item, let n):
                s.inventory[item.rawValue, default: 0] += n
            case .rainbowCharm:
                s.ownsRainbowCharm = true
                // 옛 무지개 부적은 분모를 1/32 로 고정했다 — 지금의 −8 만 주면 전국도감을
                // 채운 보상이 1/56 로 약해진다. 같은 값이 나오는 이로치 단계를 함께 얹는다
                // (`rainbowShinyTier` 참고). 이미 더 높이 올려 뒀으면 건드리지 않는다.
                s.charmTiers[ShopItem.shinyCharm.rawValue] =
                    max(s.charmTiers[ShopItem.shinyCharm.rawValue] ?? 0, CharmLadder.rainbowShinyTier)
            case .pokemon(let speciesID, let grade, let growthRate, let gender):
                // 부화(`makeHatchling`)가 굴리는 것 중 성격·이로치만 굴린다 — 지방·무늬는
                // 지금의 지급 종(레지기가스)에 없어서 안 굴린다(생기면 그때 얹는다).
                // 이로치 분모는 부적 상태를 따른다 — 확정권 뽑기와 같은 규칙.
                let natures = PokemonNature.allCases
                let nature = natures[Int(nextRandomUnit() * Double(natures.count)) % natures.count]
                let denominator = ShinyOdds.denominator(
                    shinyTier: s.charmTiers[ShopItem.shinyCharm.rawValue] ?? 0,
                    rainbowCharm: s.ownsRainbowCharm)
                let shiny = EggBalance.rollShiny(nextRandomUnit(), denominator: denominator)
                let individual = Individual(baseID: speciesID, speciesID: speciesID,
                                            pathIDs: [speciesID], shiny: shiny, gender: gender,
                                            nature: nature,
                                            obtainedAt: currentDate(), grade: grade,
                                            growthRate: growthRate)
                s.box.append(individual)
                s.dexForms.insert(DexKey.key(for: individual))
            }
        }
    }

    /// 확정권 한 장으로 알을 놓는다. 차감할 **아이템을 직접 받는다** — 등급에서 유도하면
    /// 세대권(등급을 안 정한다)이 엉뚱한 등급권을 차감한다.
    @discardableResult
    func redeemEggTicket(_ ticket: ShopItem, grade: Grade, speciesID: Int,
                         growthRate: GrowthRate = .mediumFast,
                         genderRate: Int = GenderBalance.defaultRate) -> Egg? {
        guard count(of: ticket) > 0 else { return nil }
        let shiny = EggBalance.rollShiny(nextRandomUnit(), denominator: shinyDenominator)
        guard let egg = placeEgg(grade: grade, speciesID: speciesID, shiny: shiny,
                                 growthRate: growthRate, genderRate: genderRate) else { return nil }
        mutate { Self.consume(ticket, in: &$0) }
        // **확정권 개봉도 뽑기로 센다**(사용자 결정). 같은 줄의 버튼을 눌러 같은 연출이 뜨는
        // 같은 동작이고, 박사의 상자가 확정권을 뿌리게 된 뒤로는 상자에서 받은 권으로 알을 까도
        // 목표가 안 움직이면 어긋나 보인다.
        //
        // 계수를 `placeEgg` 로 내려 한 번에 풀 수는 없다 — 파트너가 물어온 알도 그 함수를
        // 지나는데 그건 뽑은 것이 아니다. 진입점마다 의미가 달라 여기에 붙는다.
        countDailyActivity(.drawEggs)
        return egg
    }
}
