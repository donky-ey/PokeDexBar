import Foundation

/// 컬렉션 — 주제로 묶은 수집 세트. 도감 미션이 "숫자" 라면 이쪽은 "이야기" 다
/// (포켓몬 GO 의 메달, HOME 의 챌린지 자리).
///
/// **완성 = 배지.** 배지는 도감에서 파생될 뿐 받는 동작이 없다 — 모으는 것 자체가 재미다.
/// 난도 높은 몇 세트만 작은 보상을 얹고(사용자 결정), 그 수령만 기록이 남는다.
struct CollectionSet: Identifiable, Equatable, Sendable {
    let id: String
    /// 이 세트를 이루는 종들(도감 등록 기준).
    let speciesIDs: [Int]
    /// 완성 보상 — 대부분 nil(배지만). **반짝사탕은 여기 못 온다**(미션 쪽 희소성 가드와
    /// 별개 경로로 새는 걸 막는다 — 테스트가 잠근다).
    let rewards: [DexMissionReward]?
}

enum CollectionCatalog {
    /// 전체 세트. 순서가 곧 화면 순서다 — 쉬운 것부터.
    static let all: [CollectionSet] = [
        // 전승 트리오·듀오 — 배지만. 작은 세트는 완성 자체가 보상이다.
        CollectionSet(id: "legendary-birds", speciesIDs: [144, 145, 146], rewards: nil),
        CollectionSet(id: "legendary-beasts", speciesIDs: [243, 244, 245], rewards: nil),
        CollectionSet(id: "tower-duo", speciesIDs: [249, 250], rewards: nil),
        // 뮤·뮤츠·메타몽 — 복제 실험 전승(메타몽 = 실패한 뮤 복제설).
        CollectionSet(id: "clone-truth", speciesIDs: [132, 150, 151], rewards: nil),
        CollectionSet(id: "weather-trio", speciesIDs: [382, 383, 384], rewards: nil),
        CollectionSet(id: "lake-guardians", speciesIDs: [480, 481, 482], rewards: nil),
        CollectionSet(id: "tao-trio", speciesIDs: [643, 644, 646], rewards: nil),
        CollectionSet(id: "aura-trio", speciesIDs: [716, 717, 718], rewards: nil),
        CollectionSet(id: "sword-shield", speciesIDs: [888, 889, 890], rewards: nil),
        // 중간 크기 — 진화가 필요한 세트는 경험치 사탕이 어울린다(그 사탕으로 마저 진화시킨다).
        CollectionSet(id: "eevee-friends",
                      speciesIDs: [133, 134, 135, 136, 196, 197, 470, 471, 700],
                      rewards: [.item(.expCandy, 10)]),
        CollectionSet(id: "kanto-starters",
                      speciesIDs: [1, 2, 3, 4, 5, 6, 7, 8, 9],
                      rewards: [.item(.expCandy, 10)]),
        CollectionSet(id: "creation-gods", speciesIDs: [483, 484, 487, 493],
                      rewards: [.item(.expCandy, 20)]),
        // 큰 세트 — 레전더리 여섯·열하나라 확정권이 걸맞다.
        CollectionSet(id: "regi-family", speciesIDs: [377, 378, 379, 486, 894, 895],
                      rewards: [.eggTicket(.legendary)]),
        CollectionSet(id: "ultra-beasts",
                      speciesIDs: [793, 794, 795, 796, 797, 798, 799, 803, 804, 805, 806],
                      rewards: [.eggTicket(.legendary)]),
    ]

    static func progress(of set: CollectionSet, dex: Set<Int>) -> (done: Int, target: Int) {
        (set.speciesIDs.count(where: { dex.contains($0) }), set.speciesIDs.count)
    }

    static func completed(_ set: CollectionSet, dex: Set<Int>) -> Bool {
        set.speciesIDs.allSatisfy { dex.contains($0) }
    }

    /// 세트 이름 — 세 언어. `BoxSort.label` 과 같은 관례.
    static func label(_ id: String, _ lang: AppLanguage) -> String {
        let names: (String, String, String)
        switch id {
        case "legendary-birds": names = ("전설의 새", "Legendary Birds", "でんせつの とりポケモン")
        case "legendary-beasts": names = ("전설의 야수", "Legendary Beasts", "でんせつの けものポケモン")
        case "tower-duo": names = ("탑의 듀오", "Tower Duo", "とうの デュオ")
        case "clone-truth": names = ("클론의 진실", "The Clone Truth", "クローンの しんじつ")
        case "weather-trio": names = ("초대륙 트리오", "Weather Trio", "てんこうトリオ")
        case "lake-guardians": names = ("호수의 수호신", "Lake Guardians", "みずうみの ばんにん")
        case "tao-trio": names = ("타오 트리오", "Tao Trio", "タオトリオ")
        case "aura-trio": names = ("오라 트리오", "Aura Trio", "オーラトリオ")
        case "sword-shield": names = ("검과 방패", "Sword and Shield", "けんと たて")
        case "eevee-friends": names = ("이브이 프렌즈", "Eevee Friends", "イーブイフレンズ")
        case "kanto-starters": names = ("관동 스타터", "Kanto Starters", "カントーの さいしょのポケモン")
        case "creation-gods": names = ("시공의 신", "Creation Gods", "じくうの かみがみ")
        case "regi-family": names = ("레지 패밀리", "Regi Family", "レジファミリー")
        case "ultra-beasts": names = ("울트라비스트", "Ultra Beasts", "ウルトラビースト")
        default: names = (id, id, id)
        }
        switch lang { case .ko: return names.0; case .en: return names.1; case .ja: return names.2 }
    }
}
