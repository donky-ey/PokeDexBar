import Foundation

/// 앱 전체 UI 문자열 — 언어별. 단일 소스(AppLanguage)에서 파생한다.
/// 뷰는 `player.l.<key>` 로 접근하며, language 변경 시 @Observable 로 자동 재렌더된다.
/// 포켓몬 이름은 PokéAPI 다국어 데이터(EvoLine.localizedName)에서 별도로 온다.
struct L {
    let lang: AppLanguage
    init(_ lang: AppLanguage) { self.lang = lang }

    private func t(_ ko: String, _ en: String, _ ja: String) -> String {
        switch lang {
        case .ko: return ko
        case .en: return en
        case .ja: return ja
        }
    }

    // MARK: 탭
    var home: String { t("홈", "Home", "ホーム") }
    var box: String { t("박스", "Box", "ボックス") }
    /// 일본어는 `ずかん`(図鑑) — 표준 표기이고, `コレクション` 은 5탭이 되면서 세그먼트가
    /// 360pt 팝오버를 12pt 넘겨 잘렸다(실측). 탭을 더할 땐 라벨 폭부터 재라.
    var collection: String { t("도감", "Collection", "ずかん") }
    /// 도감 폼 상세 — 원종 행의 이름(폼 이름이 없는 행).
    var dexBaseForm: String { t("원종", "Original", "原種") }
    /// 도감 폼 상세 헤더의 진행 표시.
    func dexFormProgress(_ owned: Int, _ total: Int) -> String {
        t("모습 \(owned)/\(total)", "Forms \(owned)/\(total)", "すがた \(owned)/\(total)")
    }
    var bag: String { t("가방", "Bag", "バッグ") }

    // MARK: 오늘의 목표 — 하루짜리 과제 셋
    /// **박사가 내미는 의뢰**로 말한다(사용자 결정). 보상이 박사 포인트이고 자리도 박사의
    /// 제안 바로 아래라, "오늘의 목표"라는 주인 없는 이름보다 누가 시킨 일인지가 분명하다.
    var dailySection: String { t("박사의 의뢰", "The Professor's requests", "はかせの いらい") }
    /// 과제 문장. **목표치를 문장 안에 넣는다** — "알 뽑기 · 3" 처럼 쪼개면 3이 무엇의 3인지
    /// 읽는 데 한 박자가 든다.
    func dailyQuestLabel(_ kind: DailyQuest.Kind, _ target: Int) -> String {
        switch kind {
        case .drawEggs: t("알 \(target)번 뽑기", "Draw \(target) egg\(target == 1 ? "" : "s")",
                          "タマゴを \(target)かい ひく")
        case .hatchEggs: t("알 \(target)개 부화시키기", "Hatch \(target) egg\(target == 1 ? "" : "s")",
                           "タマゴを \(target)こ かえす")
        case .evolve: t("\(target)마리 진화시키기", "Evolve \(target) Pokémon", "\(target)ひき しんかさせる")
        case .useCandy: t("경험치 사탕 \(target)개 쓰기", "Use \(target) EXP Candy",
                          "けいけんちアメを \(target)こ つかう")
        case .sendToProfessor: t("박사에게 \(target)마리 보내기", "Send \(target) to the Professor",
                                 "はかせに \(target)ひき おくる")
        }
    }
    /// 보상 표시 — 박사 포인트.
    func dailyQuestReward(_ points: Int) -> String {
        t("+\(points)P", "+\(points)P", "+\(points)P")
    }
    /// 셋을 다 받은 날의 덤.
    var dailyBonusLabel: String {
        t("오늘 의뢰를 모두 끝냈어요", "Every request done today", "きょうの いらいを すべて たっせい")
    }

    // MARK: 도감 미션
    var missionSection: String { t("미션", "Missions", "ミッション") }
    var missionClaim: String { t("받기", "Claim", "うけとる") }
    func missionClaimableBadge(_ n: Int) -> String {
        t("받을 수 있음 \(n)", "\(n) ready", "うけとれる \(n)")
    }
    func missionSpecies(_ n: Int) -> String {
        t("\(n)종 등록", "Register \(n) species", "\(n)しゅ とうろく")
    }
    func missionGeneration(_ n: Int) -> String {
        t("\(n)세대 완성", "Complete Gen \(n)", "だい\(n)せだい かんせい")
    }
    var missionCompletion: String { t("전국도감 완성", "Complete the National Dex", "ぜんこくずかん かんせい") }
    var collectionSection: String { t("컬렉션", "Collections", "コレクション") }
    // MARK: 도감 상세
    var dexHeight: String { t("키", "Height", "たかさ") }
    var dexWeight: String { t("몸무게", "Weight", "おもさ") }
    var dexEntryLoading: String { t("도감을 펼치는 중…", "Opening the Dex…", "ずかんを ひらいています…") }
    var dexEntryUnavailable: String {
        t("도감 정보를 받지 못했어요. 잠시 뒤 다시 열어 주세요.",
          "Couldn't fetch the Dex entry. Try again shortly.",
          "ずかんの じょうほうを とれませんでした。しばらくして ひらいてください。")
    }
    /// 미등록 종 — 본가처럼 정보를 가린다.
    var dexEntryUnknown: String { t("???", "???", "???") }
    func dexFormsButton(_ n: Int) -> String {
        t("모습 \(n)종 보기", "See \(n) forms", "すがた \(n)しゅを みる")
    }
    var collectionCompleteBadge: String { t("완성", "Complete", "かんせい") }
    /// 부적 단계 배지 — 상점에서 "지금 몇 단계인가".
    func charmTierBadge(_ tier: Int) -> String {
        t("\(tier)단계", "Tier \(tier)", "\(tier)だんかい")
    }
    /// 더 올릴 데가 없을 때의 버튼 — "보유" 로는 최고 단계인지 1단계인지 구분이 안 된다.
    var charmMaxTier: String { t("최고 단계", "Max tier", "さいこうだんかい") }
    /// **부적이 무엇을 올리나.** 값만 "2.00배" 라고 적으면 무엇의 배율인지 알 수가 없다
    /// (사용자 지적) — 값 앞에 항상 이 이름이 붙는다.
    func charmEffectName(_ item: ShopItem) -> String {
        switch item {
        case .expCharm: t("경험치", "EXP", "けいけんち")
        case .fortuneCharm: t("재화", "Currency", "所持金")
        case .shinyCharm: t("이로치", "Shiny", "ひかる")
        default: item.label(lang)
        }
    }
    /// 그 단계의 값. **이로치만 분모로 말한다** — 사용자가 아는 표기가 1/64 쪽이고,
    /// "1.08배" 로는 확률이 얼마인지 알 수 없다.
    func charmEffectValue(_ item: ShopItem, tier: Int) -> String {
        if item == .shinyCharm {
            return "1/\(ShinyOdds.denominator(shinyTier: tier, rainbowCharm: false))"
        }
        let value = String(format: "%.2f", CharmLadder.multiplier(item, tier: tier))
        return t("\(value)배", "\(value)×", "\(value)倍")
    }
    /// 상점 한 줄 — 지금 값과, 다음 단계의 값. 다음이 몇 단계인지 같이 적어야 버튼의
    /// 값이 무엇을 사는 값인지 이어진다.
    func charmShopEffect(_ item: ShopItem, tier: Int) -> String {
        let now = "\(charmEffectName(item)) \(charmEffectValue(item, tier: tier))"
        guard CharmLadder.price(tier: tier + 1) != nil else { return now }
        return "\(now) → \(charmTierBadge(tier + 1)) \(charmEffectValue(item, tier: tier + 1))"
    }
    /// 가방 한 줄 — 가진 것을 보는 화면이라 지금 단계와 지금 효과만 말한다.
    func charmBagEffect(_ item: ShopItem, tier: Int) -> String {
        "\(charmTierBadge(tier)) · \(charmEffectName(item)) \(charmEffectValue(item, tier: tier))"
    }
    var missionClaimedToBag: String {
        t("가방에 담았어요", "Added to your Bag", "バッグに いれました")
    }
    /// 포켓몬을 주는 컬렉션 보상의 수령 확인 — 가방이 아니라 박스로 간다.
    var collectionJoinedBox: String {
        t("박스에 합류했어요", "Joined your Box", "ボックスに くわわりました")
    }
    /// 상점 알 뽑기의 확정권 버튼 — 등급 이름과 남은 장수.
    func shopTicketDraw(_ ticket: String, _ n: Int) -> String {
        t("\(ticket) ×\(n)", "\(ticket) ×\(n)", "\(ticket) ×\(n)")
    }
    var shop: String { t("상점", "Shop", "ショップ") }

    // MARK: 가방 탭 — 가진 것을 보는 화면. 쓰는 건 개체 상세에서 한다.
    var bagEmptyTitle: String { t("가방이 비어 있어요", "Your bag is empty", "バッグは空です") }
    var bagEmptyHint: String {
        t("파트너로 둔 포켓몬이 자기에게 필요한 도구를 물어 와요.\n사탕과 부적은 상점에서 살 수 있어요.",
          "Your partner finds the items it needs.\nCandy and charms are sold in the shop.",
          "パートナーが自分にひつような道具をもってきます。\nアメとおまもりはショップで買えます。")
    }

    // MARK: 상점 탭
    var shopWallet: String { t("재화", "Currency", "所持金") }
    var shopEggDraw: String { t("알 뽑기", "Egg draw", "タマゴ抽選") }
    var shopDrawing: String { t("뽑는 중…", "Drawing…", "抽選中…") }
    var shopDrawButton: String { t("뽑기", "Draw", "引く") }
    var shopDrawFetchFailed: String {
        t("부화 후보를 받지 못했어요. 잠시 뒤 다시 시도해 주세요.",
          "Couldn't fetch hatch candidates. Please try again shortly.",
          "ふ化候補を取得できませんでした。しばらくして再試行してください。")
    }
    var shopDrawUnavailable: String {
        t("지금은 뽑을 수 없어요. 재화와 빈 슬롯을 확인해 주세요.",
          "Can't draw right now. Check your currency and open slots.",
          "今は引けません。所持金と空きスロットを確認してください。")
    }
    /// 세대 확정권이 걸러낸 후보가 하나도 없을 때 — 네트워크 실패가 아니라 그 세대에 맞는
    /// 종을 못 찾은 것이라 `shopDrawFetchFailed`("부화 후보를 받지 못했어요")를 쓰면 거짓말이 된다.
    var shopDrawNoMatchingSpecies: String {
        t("이 확정권에 맞는 후보를 찾지 못했어요. 잠시 뒤 다시 시도해 주세요.",
          "Couldn't find a match for this ticket. Please try again shortly.",
          "このチケットに合う候補が見つかりませんでした。しばらくして再試行してください。")
    }
    func shopFreeSlots(_ free: Int, _ total: Int) -> String {
        t("빈 슬롯 \(free) / \(total)", "Open slots \(free) / \(total)", "空きスロット \(free) / \(total)")
    }
    var shopSlotSection: String { t("부화 슬롯", "Hatch slots", "ふ化スロット") }
    func shopSlotUpgrade(_ from: Int, _ to: Int) -> String {
        t("슬롯 늘리기 (\(from) → \(to))", "Add a slot (\(from) → \(to))", "スロット追加 (\(from) → \(to))")
    }
    var shopSlotsMaxed: String { t("슬롯을 최대까지 늘렸어요", "Slots are maxed out", "スロットは最大まで増やしました") }
    /// 진화 도구 — 파는 목록이 아니라 모은 것을 보는 목록이다.
    var shopEvolutionSection: String { t("진화 도구", "Evolution items", "しんかのどうぐ") }
    /// 폼 도구 — 진화 도구와 같은 규칙(못 사고, 안 없어진다).
    var shopFormItemSection: String { t("폼 도구", "Form items", "フォルムのどうぐ") }
    /// 도구는 못 산다는 사실 자체를 말해 줘야 한다 — 안 그러면 상점에 있는데 살 수가 없어 보인다.
    var shopEvolutionHint: String {
        t("살 수 없어요. 파트너로 둔 포켓몬이 자기에게 필요한 도구를 물어 와요. 한 번 얻으면 계속 쓸 수 있어요.",
          "Not for sale. Your partner finds the item it needs. Once found, it is yours for good.",
          "こうにゅうできません。パートナーが自分にひつような道具をもってきます。一度手にいれるとずっと使えます。")
    }
    /// 아직 못 채운 함께한 시간. 도구와 달리 **얼마나 남았는지**가 곧 안내다 — 어디서 얻는지는
    /// 물을 것이 없고, 기다릴 값만 알면 된다.
    func evolveNeedsTime(_ remaining: String) -> String {
        t("\(remaining) 더 함께해야 해요", "\(remaining) more together", "あと\(remaining)一緒に")
    }
    var shopItemSection: String { t("아이템", "Items", "アイテム") }
    var shopItemOwned: String { t("보유 중", "Owned", "所持中") }
    var shopItemOwnedButton: String { t("보유", "Owned", "所持") }
    /// 뽑기 결과 연출 — 등급은 `Grade.label` 이 말하고, 이 줄은 그 다음에 무슨 일이 생기는지 말한다.
    var drawResultHatching: String {
        t("부화를 시작했어요", "It's incubating now", "ふ化がはじまりました")
    }
    var drawResultShiny: String {
        t("✨ 이로치가 들어 있어요!", "✨ There's a shiny inside!", "✨ 色違いが入っています！")
    }

    // MARK: 스타터 픽커 (첫 실행 — 27마리 중 1마리 선택)
    var starterPickerTitle: String { t("함께 시작할 포켓몬을 고르세요", "Choose your starting Pokémon", "一緒に始めるポケモンを選んでください") }
    var starterPickerSubtitle: String {
        t("고른 포켓몬이 첫 파트너가 돼요. 토큰을 쓸수록 경험치가 쌓여요.",
          "Your pick becomes your first partner. The more tokens you use, the more experience it earns.",
          "選んだポケモンが最初のパートナーになります。トークンを使うほど経験値がたまります。")
    }
    var starterPickFailed: String {
        t("선택이 반영되지 않았어요. 다시 눌러주세요.",
          "That choice didn't go through. Please try again.",
          "選択が反映されませんでした。もう一度お試しください。")
    }
    func generationLabel(_ generation: Int) -> String {
        t("\(generation)세대", "Gen \(generation)", "第\(generation)世代")
    }

    // MARK: 박스 (보유 개체)
    var partnerBadge: String { t("파트너", "Partner", "パートナー") }
    var makePartner: String { t("파트너로", "Make partner", "パートナーにする") }
    var evolve: String { t("진화", "Evolve", "しんか") }
    func evolveTo(_ name: String) -> String { t("\(name) 로 진화", "Evolve to \(name)", "\(name)にしんか") }
    /// 도구가 결과 모습을 가르는 갈래의 버튼 — 무엇을 쓰는지가 곧 어떤 모습이 되는지다.
    /// 조사는 `Josa` 로 고른다(`testNoHardcodedJosaAnywhere`) — 도구 이름은 데이터에서 온다.
    func evolveWith(_ item: String) -> String {
        t("\(item)\(Josa.roEuro(item)) 진화", "Evolve with \(item)", "\(item)でしんか")
    }
    /// 사탕 사용 버튼 — 남은 개수를 라벨에 달아 상점에 다시 안 가도 재고를 알 수 있게.
    /// 이름은 상점 품목(`ShopItem.label`)과 같은 말을 쓴다.
    func useExpCandy(_ remaining: Int) -> String {
        t("경험치 사탕 ×\(remaining)", "EXP Candy ×\(remaining)", "けいけんちアメ ×\(remaining)")
    }
    func useShinyCandy(_ remaining: Int) -> String {
        t("반짝이는 사탕 ×\(remaining)", "Shiny Candy ×\(remaining)", "ひかるアメ ×\(remaining)")
    }
    /// 마사지 쿠폰 버튼 — 남은 장수를 함께 적는다(사탕 버튼과 같은 관례).
    func useMassageCoupon(_ count: Int) -> String {
        t("마사지 쿠폰 쓰기 (\(count))", "Use Massage Coupon (\(count))",
          "マッサージけんを使う (\(count))")
    }
    // MARK: 발견 카드 — 파트너가 물어 온 것을 알려 준다. 확인은 흐름을 막지 않는다.
    func discoveryFoundBy(_ name: String, _ count: Int) -> String {
        t("\(name)\(Josa.iGa(name)) 도구를 \(count)개 물어 왔어요",
          "\(name) found \(count) item\(count == 1 ? "" : "s")",
          "\(name)が道具を\(count)個もってきました")
    }
    func discoveryFoundBySeveral(_ species: Int, _ count: Int) -> String {
        t("파트너 \(species)마리가 도구를 \(count)개 물어 왔어요",
          "\(species) partners found \(count) items",
          "パートナー\(species)ひきが道具を\(count)個もってきました")
    }
    var discoveryAcknowledge: String { t("확인했어요", "Got it", "かくにん") }

    /// 홈 파트너 카드의 진화 가능 배지 — 실제 진화 실행은 박스에서.
    var evolutionReadyBadge: String { t("진화 가능", "Can evolve", "しんか可能") }
    /// 상세 화면 — 그리드에서 개체를 눌러 들어간다. 사탕·진화·파트너 지정이 모두 여기 있다.
    var backToBox: String { t("박스", "Box", "ボックス") }
    var boxEmpty: String { t("아직 가진 포켓몬이 없어요", "No Pokémon yet", "まだポケモンがいません") }
    func boxCount(_ count: Int) -> String { t("\(count)마리", "\(count)", "\(count)ひき") }
    /// 보관함 상자 이름과 사용 칸 — 본가 PC 처럼 고정 30칸 상자를 넘겨 본다.
    func boxTitle(_ number: Int) -> String { t("박스 \(number)", "Box \(number)", "ボックス \(number)") }
    func boxSlotUsage(_ used: Int, _ total: Int) -> String { "\(used) / \(total)" }
    /// 박스 헤더의 정렬 메뉴. **상태가 아니라 명령**이라 "정렬 기준"이 아니라 "정리"라고 부른다.
    var boxSearchPlaceholder: String { t("이름 검색", "Search by name", "なまえでけんさく") }
    /// 검색이 안 맞은 것과 박스가 빈 것은 다른 상태다 — 같은 화면을 보여주면 왜 비었는지 모른다.
    func boxSearchNoResults(_ query: String) -> String {
        t("\"\(query)\" 와 맞는 아이가 없어요", "Nothing matches \"\(query)\"",
          "\"\(query)\" に合う子がいません")
    }
    var boxSortMenu: String { t("정리", "Tidy", "せいり") }
    var detailNature: String { t("성격", "Nature", "せいかく") }
    // MARK: 별표 — 즐겨찾기 겸 보호(포켓몬 GO 규칙)
    var starOn: String { t("별표", "Star", "★をつける") }
    var starOff: String { t("별표 해제", "Unstar", "★をはずす") }
    var starredCannotSend: String {
        t("별표한 포켓몬은 박사에게 보낼 수 없어요. 보내려면 별표를 해제하세요.",
          "Starred Pokémon can't be sent to the Professor. Unstar it first.",
          "★をつけたポケモンは はかせに おくれません。おくるには★をはずしてください。")
    }
    var detailGrade: String { t("등급", "Grade", "ランク") }
    /// 레벨 표시 — 박스 칸의 작은 배지와 상세 화면이 함께 쓴다.
    func levelLabel(_ level: Int) -> String { t("Lv.\(level)", "Lv.\(level)", "Lv.\(level)") }
    /// 100레벨에 닿으면 "다음 레벨까지"가 성립하지 않는다 — 0이라고 적으면 다음 레벨이 있는데
    /// 코앞인 것처럼 읽힌다. 더 갈 곳이 없다는 사실 자체를 말한다.
    var maxLevelLabel: String { t("최고 레벨", "Max level", "さいこうレベル") }
    /// 다음 레벨까지 남은 경험치.
    func expToNextLevel(_ remaining: String) -> String {
        t("다음 레벨까지 \(remaining)", "\(remaining) to next level", "つぎのレベルまで \(remaining)")
    }
    /// 알 계량기 — 파트너로 지내는 동안 채워진다(더 이상 최종형에만 국한되지 않는다).
    var eggProgressLabel: String { t("알", "Egg", "タマゴ") }
    /// 이 개체를 파트너로 두고 함께 쓴 토큰 누적 — 진화해도 안 줄어드는 "같이 일한 기록".
    var detailPartnerTokens: String { t("함께 쓴 토큰", "Tokens together", "一緒に使ったトークン") }
    var detailPartnerTime: String { t("함께한 시간", "Time together", "一緒の時間") }
    /// 리본 — 오래 함께한 개체가 파트너일 때 토큰을 쓸수록 경험치 사탕을 만든다.
    /// 리본이 하는 일 둘을 한 줄로 — 따로 쓰면 세 줄이 되고 그 아래 목록에 묻힌다.
    func ribbonRate(_ tokens: String, percent: Int) -> String {
        t("\(tokens)마다 사탕 · 도구 탐색 \(percent)%",
          "1 candy per \(tokens) · \(percent)% item find",
          "\(tokens)ごとにアメ · 道具さがし\(percent)%")
    }
    var ribbonNextCandy: String { t("다음 사탕", "Next candy", "つぎのアメ") }
    var formSection: String { t("폼 체인지", "Change form", "フォルムチェンジ") }

    func ribbonCandyRate(_ tokens: String) -> String {
        t("토큰 \(tokens)마다 사탕 1개", "1 candy per \(tokens) tokens", "トークン\(tokens)ごとにアメ1個")
    }
    /// 리본이 하는 일은 둘이다 — 사탕을 만들고, **그때마다 도구를 찾는다**. 예전에는 사탕만
    /// 적혀 있어 리본이 사탕 공장으로만 읽혔고, 도구가 어디서 오는지 화면에 없었다.
    func ribbonForageRate(_ percent: Int) -> String {
        t("사탕이 나올 때마다 도구를 찾아요 (\(percent)%)",
          "Each candy is also a \(percent)% chance to find an item",
          "アメが出るたびに道具をさがします(\(percent)%)")
    }
    /// 지금 무엇을 노리고 있나 — 자기에게 필요한 것만 물어 오므로 대상이 정해져 있다.
    func ribbonForageTargets(_ names: String) -> String {
        t("찾는 중: \(names)", "Looking for: \(names)", "さがしもの: \(names)")
    }
    func ribbonForageMore(_ count: Int) -> String {
        t("외 \(count)개", "and \(count) more", "ほか\(count)個")
    }
    var ribbonForageDone: String {
        t("필요한 도구를 다 모았어요", "It has found every item it needs", "ひつような道具はすべて集めました")
    }
    func ribbonNext(_ name: String, _ remaining: String) -> String {
        t("\(remaining) 더 함께하면 \(name)", "\(name) in \(remaining) more together",
          "あと\(remaining)一緒にいると\(name)")
    }
    var ribbonNone: String {
        t("함께 다니면 리본이 생겨요", "Ribbons come from time together", "一緒にいるとリボンがつきます")
    }
    /// 함께한 시간 표기 — 가장 큰 단위 둘까지만. 초 단위는 "방금 만난" 경우에만 의미가 있다.
    func togetherDays(_ days: Int, _ hours: Int) -> String {
        t("\(days)일 \(hours)시간", "\(days)d \(hours)h", "\(days)日\(hours)時間")
    }
    func togetherHours(_ hours: Int, _ minutes: Int) -> String {
        t("\(hours)시간 \(minutes)분", "\(hours)h \(minutes)m", "\(hours)時間\(minutes)分")
    }
    func togetherMinutes(_ minutes: Int) -> String {
        t("\(minutes)분", "\(minutes)m", "\(minutes)分")
    }
    /// 아직 못 가는 진화 갈래 — 접힌 줄. 이유는 펼쳤을 때 한 번만 적는다.
    func evolutionLocked(_ count: Int) -> String {
        t("조건이 필요한 진화 \(count)", "\(count) locked", "条件がひつような進化 \(count)")
    }
    var evolutionLockedHint: String {
        t("도구는 파트너로 두면 물어 와요", "Your partner finds the items",
          "道具はパートナーがもってきます")
    }
    /// 접힌 줄에 들어갈 짧은 조건 이름 — 문장이 아니라 이름이어야 한 줄에 여럿이 들어간다.
    var evolveNeedsFriendshipShort: String { t("함께 다니기", "Time together", "一緒にいること") }
    /// 걸음 조건의 짧은 이름 — 친밀도와 같은 자리(접힌 줄)에 쓴다.
    var evolveNeedsWalkedShort: String { t("함께 걷기", "Walking together", "一緒に歩くこと") }
    /// 도구가 셋 이상인 갈래의 접힌 줄 — 이름을 다 늘어놓으면 한 줄을 넘는다(마빌크는 일곱이다).
    func evolveNeedsOneOf(_ first: String, _ count: Int) -> String {
        t("\(first) 등 \(count)종", "\(first) or \(count - 1) more", "\(first)など\(count)種")
    }
    /// 소유 조건 안내 — 필요한 종의 이름은 갈래 줄에 이미 나오므로, 여기서는 그게 "박스에 갖고
    /// 있어야 한다"는 조건임을 짚는다(도구 안내가 얻는 방법을 짚는 것과 같은 역할).
    var evolutionOwnsHint: String {
        t("그 포켓몬을 박스에 갖고 있어야 열려요", "You need that Pokémon in your box",
          "そのポケモンをボックスに持っている必要があります")
    }

    var detailMaxStage: String { t("더 진화하지 않아요", "Fully evolved", "これいじょうしんかしない") }
    /// 알 발견 버튼 — 사육가가 알을 발견해 건네주는 원작 문구 그대로다. 그래서 버튼 하나가
    /// 곧 "받는다" 동작이 된다. 종 이름은 그 개체의 baseID(원종)다.
    func eggFound(_ name: String) -> String {
        t("\(name)의 알이 발견되었어요!", "You found a \(name) Egg!", "\(name)のタマゴを みつけた！")
    }
    /// 빈 부화 슬롯이 없어 버튼이 비활성일 때 — 경험치는 잃지 않는다는 사실이 같이 보여야 한다.
    var eggFoundNoFreeSlot: String {
        t("부화 슬롯이 다 찼어요 — 경험치는 그대로 남아 있어요",
          "All hatch slots are full — your experience stays banked",
          "ふ化スロットがいっぱいです — けいけんちはそのまま残ります")
    }
    /// 홈의 알 발견 알림 — 파트너가 곁에서 알을 건네는 장면이라 상세 화면(`eggFound`)과 문구가
    /// 다르다. 둘 다 같은 뜻이지만 서 있는 자리가 다르다: 상세는 그 개체 자신의 진행,
    /// 여기는 파트너가 지금 막 가져온 것.
    ///
    /// **`name` 은 알의 종이지 가져온 아이가 아니다.** 리자몽 파트너가 파이리 알을 가져온다.
    /// 한국어·일본어는 주어를 생략해 "(파트너가) 파이리의 알을 가져왔다"로 자연히 읽히지만,
    /// 영어는 주어를 세워야 해서 처음에 "Charmander brought you an Egg!" 로 나갔다 —
    /// 파이리가 가져온 것이 된다. 영어는 파트너를 주어로 두고 종은 알을 꾸미게 한다.
    func partnerFoundEgg(_ name: String) -> String {
        t("\(name)의 알을 가져왔어요!",
          "Your partner brought a \(name) Egg!",
          "\(name)のタマゴを もってきました！")
    }
    var detailPartnerOnlyExp: String {
        t("경험치는 파트너만 쌓여요 — 사탕으로도 올릴 수 있어요",
          "Only your partner earns EXP — candy works too",
          "けいけんちはパートナーのみ — アメでも上げられます")
    }
    /// 알 계량기도 경험치와 같은 규칙(파트너만 쌓인다)을 따른다 — 문구는 따로 둔다. "사탕으로도
    /// 올릴 수 있어요"가 경험치 사탕에만 해당해 알에는 안 맞는 말이 되기 때문이다.
    var detailPartnerOnlyEgg: String {
        t("알은 파트너만 쌓여요", "Only your partner fills the Egg meter",
          "タマゴはパートナーのみたまります")
    }
    /// 박사에게 보내기 — 받을 포인트를 제목에 적어, 누르기 전에 값을 알 수 있게 한다.
    func sendToProfessor(_ points: Int) -> String {
        t("박사에게 보내기 · +\(points)P", "Send to the Professor · +\(points)P",
          "はかせにおくる · +\(points)P")
    }
    var sendConfirmNoReturn: String {
        t("돌아오지 않아요. 정말 보낼까요?",
          "This cannot be undone. Send it?",
          "もどってきません。おくりますか？")
    }
    var sendConfirmAgain: String {
        t("한 번 더 물을게요 — 다시 만나기 어려운 아이예요",
          "Asking once more — this one is hard to come by",
          "もういちどだけ — なかなか出会えない子です")
    }
    var sendCancel: String { t("그만두기", "Keep it", "やめる") }
    var sendNow: String { t("보내기", "Send", "おくる") }
    /// 박스의 선택 모드 — 여러 마리를 골라 한 번에 보낸다.
    var bulkSelect: String { t("선택", "Select", "えらぶ") }
    var bulkDone: String { t("완료", "Done", "おわり") }
    func bulkPicked(_ count: Int, _ points: Int) -> String {
        t("\(count)마리 · +\(points)P", "\(count) selected · +\(points)P",
          "\(count)ひき · +\(points)P")
    }
    func bulkConfirm(_ count: Int) -> String {
        t("\(count)마리를 보냅니다. 돌아오지 않아요.",
          "Sending \(count). This cannot be undone.",
          "\(count)ひきをおくります。もどってきません。")
    }
    /// 위험한 아이 이름 앞에 붙는 표식 — 이로치. 이름만으론 "왜 불려 있는지" 안 보인다
    /// (파이리가 두 마리면 이로치가 어느 쪽인지 이름만으로 모른다). `BulkRelease.riskyLabel`
    /// 이 이 표식과 `Grade.label` 을 조합해 실제로 붙는 문자열을 만든다.
    var riskyShinyMark: String { t("이로치", "Shiny", "色違い") }
    /// 배치에 이로치·전설이 섞였을 때 **그 아이들만 이름으로** 불러 준다 — 스무 마리를 다
    /// 나열하면 아무도 안 읽는다. 조사는 합쳐진 목록의 마지막 글자에 붙는다
    /// (`Josa.iGa` — 받침 **있는** 이름 뒤에 "가" 를 고정하면 "리자몽가" 가 된다.
    ///  라인이 아직 없을 때의 `#번호` 폴백도 마찬가지로 "#1가" 가 된다).
    func bulkConfirmRisky(_ names: String) -> String {
        t("\(names)\(Josa.iGa(names)) 들어 있어요", "\(names) is in this batch",
          "\(names)がふくまれています")
    }
    var professorOffersTitle: String { t("박사의 제안", "The Professor's offer", "はかせのていあん") }
    func researchPoints(_ points: Int) -> String {
        t("\(points)P", "\(points)P", "\(points)P")
    }
    var offerTaken: String { t("데려갔어요", "Taken", "つれていきました") }
    func offerPrice(_ points: Int) -> String {
        t("\(points)P 로 데려가기", "Take for \(points)P", "\(points)Pでつれていく")
    }
    var professorOffersEmpty: String {
        t("오늘의 제안을 준비하고 있어요", "Getting today's offer ready",
          "きょうのていあんをじゅんびしています")
    }
    /// 가려진 카드에 적히는 말. **세 칸이 같은 문구**를 쓴다 — 칸마다 다르면 그 차이가 곧 힌트다.
    var offerOpen: String { t("열어보기", "Open", "あけてみる") }
    var detailNoCandy: String {
        t("가진 사탕이 없어요 (상점)", "No candy yet (Shop)", "アメがありません(ショップ)")
    }
    /// 폼 변경 버튼 — 바뀔 모습 이름과 남은 아이템 개수.
    /// 폼으로 바꾸는 버튼. `remaining` 이 0 이면 개수를 안 붙인다 — 물어 온 도구는
    /// 없어지지 않아 개수가 의미 없고, "×1" 이 붙어 있으면 소모품으로 오해한다.
    func changeToForm(_ name: String, remaining: Int) -> String {
        remaining > 0 ? "\(name) ×\(remaining)" : name
    }
    /// 폼이 있는 종인데 아이템이 없을 때 — 어디서 구하는지 알려준다.
    func formNeedsItem(_ item: String) -> String {
        t("\(item)\(Josa.iGa(item)) 있으면 폼을 바꿀 수 있어요 (상점)",
          "\(item) changes its form (Shop)",
          "\(item)があればフォルムを変えられます(ショップ)")
    }
    /// 물어 오는 폼 도구 — 상점에 없으므로 파트너로 두라고 말해야 한다.
    func formNeedsForagedItem(_ item: String) -> String {
        t("\(item) 필요 · 파트너로 두면 물어 와요",
          "Needs \(item) · set as partner and it will find one",
          "\(item)がひつよう · パートナーにすると持ってきます")
    }
    /// 합체 폼 — 도구가 아니라 **상대 포켓몬**이 없는 경우. 할 일이 전혀 달라서 따로 말한다.
    func formNeedsFusionPartner(_ species: String) -> String {
        t("\(species)\(Josa.iGa(species)) 박스에 있어야 해요",
          "Needs \(species) in your box",
          "ボックスに\(species)がひつようです")
    }
    var revertForm: String { t("원래 폼으로", "Revert form", "もとのフォルムに") }

    // MARK: 세이브 봉인
    var tamperedBadge: String { t("조작된 세이브", "Edited save", "改変されたセーブ") }
    var tamperedExplanation: String {
        t("세이브 파일을 직접 고친 흔적이 있어요. 스프라이트가 위아래로 뒤집힌 채로 남아요 — 진행에는 영향이 없어요.",
          "This save was edited by hand. Sprites stay upside down — it doesn't affect progress.",
          "セーブファイルを直接編集した記録があります。スプライトは上下反転のままです — 進行には影響しません。")
    }

    // MARK: 홈 — 부화 슬롯
    var eggSlotsHeader: String { t("부화 중", "Hatching", "ふ化中") }
    /// 자리가 없어 못 뽑을 때 **확률 줄 대신** 서는 문장. 회색 버튼만 두면 왜 안 눌리는지
    /// 말해 주는 곳이 없다 — 지갑 부족은 헤더에 지갑과 값이 나란히 서서 이미 읽힌다.
    var eggSlotsFull: String { t("부화 칸이 꽉 찼어요", "Every hatching slot is full",
                                 "ふ化スロットがいっぱいです") }
    /// 배지에 마우스를 올렸을 때 — 누구 덕인지 짚어 준다.
    func eggWarmedBy(_ name: String) -> String {
        t("\(name)의 도움으로 부화가 빨라졌어요",
          "\(name) is keeping your eggs warm — they hatch in half the time",
          "\(name) のおかげでふ化が早くなっています")
    }
    /// 이름을 아직 못 받아온 경우 — 라인은 네트워크로 오므로 첫 순간엔 비어 있을 수 있다.
    var eggWarmedHint: String {
        t("불꽃몸·마그마의무장·증기기관을 가진 아이가 박스에 있어 부화가 절반으로 빨라져요",
          "A Pokémon with Flame Body, Magma Armor or Steam Engine is in your box — eggs hatch in half the time",
          "ほのおのからだ・マグマのよろい・じょうききかんを持つ子がボックスにいて、ふ化が半分の時間になります")
    }
    var eggHatchingNow: String { t("부화!", "Hatched!", "ふ化!") }
    /// 익은 알을 거두는 버튼 — 누르기 전까지 알은 슬롯에 남는다.
    var eggClaim: String { t("확인", "Open", "かくにん") }
    var hatchedMovedToBox: String {
        t("박스에 들어갔어요", "Added to your Box", "ボックスに入りました")
    }
    /// 아이템 연출의 아랫줄 — 어디로 갔는지 말한다.
    var itemDrawLanded: String { t("가방에 넣었어요", "Added to your Bag", "バッグに入れました") }
    /// 개수가 둘 이상일 때의 표기 — "×3" 은 곱셈 기호와 숫자라 세 언어가 다를 이유가 없다
    /// (상점 목록의 `"×\(owned)"` 도 같은 표기를 쓴다). `t()` 로 감싸지 않는다 — 세 갈래가
    /// 똑같은 문자열이면 그 래핑 자체가 거짓 신호다.
    func itemDrawCount(_ count: Int) -> String { "×\(count)" }
    var professorBoxTitle: String { t("박사의 상자", "Professor's Box", "はかせのはこ") }
    func itemDrawNeedsPoints(_ points: Int) -> String {
        t("\(points)포인트가 필요해요", "You need \(points) points", "\(points)ポイントが必要です")
    }
    var itemDrawSoldOut: String {
        t("오늘은 여기까지예요", "That is all for today", "きょうはここまでです")
    }
    var itemDrawButton: String { t("상자 열기", "Open the box", "はこを開ける") }
    /// 버튼에 값을 얹는다 — **누르는 곳과 치르는 값이 같은 자리**에 있어야 한다. 각주에 두었더니
    /// "이번에 얼마 내는지 모르겠다"가 됐다(사용자 지적). 알 뽑기 타일이 값을 안에 적는 것과 같다.
    var itemDrawButtonFree: String {
        t("상자 열기 · 무료", "Open the box · free", "はこを開ける · むりょう")
    }
    func itemDrawButtonPriced(_ points: Int) -> String {
        t("상자 열기 · \(points)P", "Open the box · \(points)P", "はこを開ける · \(points)P")
    }
    /// **사다리를 미리 말한다.** 첫 판이 무료라고만 하면 연타하다가 세 번째에 값이 네 배가 된 것을
    /// 뒤늦게 안다(사용자 지적). 뽑기 전에도 다음 값이 보여야 한다.
    func itemDrawLadder(_ next: Int) -> String {
        t("값은 그날 안에서 두 배씩 올라요 — 다음 판 \(next)P",
          "The price doubles with each draw today — next is \(next)P",
          "ねだんはその日のうちに倍ずつ上がります — つぎは\(next)P")
    }
    /// 확률 줄에 서는 세대 확정권의 이름 — 세대 번호는 뽑을 때 정해지므로 여기서는 안 적는다.
    var itemDrawGenerationEgg: String { t("세대 알", "Gen Egg", "せだいタマゴ") }
    /// 확률 줄에 서는 등급 확정권의 이름 — 등급 이름(`Grade.label`)에서 유도한다.
    func itemDrawGradeEgg(_ grade: String) -> String {
        t("\(grade) 알", "\(grade) Egg", "\(grade)タマゴ")
    }
    func eggCountdownDaysHours(_ days: Int, _ hours: Int) -> String {
        t("\(days)일 \(hours)시간", "\(days)d \(hours)h", "\(days)日\(hours)時間")
    }
    func eggCountdownHoursMinutes(_ hours: Int, _ minutes: Int) -> String {
        t("\(hours)시간 \(minutes)분", "\(hours)h \(minutes)m", "\(hours)時間\(minutes)分")
    }
    func eggCountdownMinutesSeconds(_ minutes: Int, _ seconds: Int) -> String {
        t("\(minutes)분 \(seconds)초", "\(minutes)m \(seconds)s", "\(minutes)分\(seconds)秒")
    }
    func eggCountdownSeconds(_ seconds: Int) -> String {
        t("\(seconds)초", "\(seconds)s", "\(seconds)秒")
    }

    // MARK: 헤더 (오늘/주/월)
    var todayTokens: String { t("오늘 사용한 토큰", "Today's tokens", "本日のトークン") }
    var thisWeek: String { t("이번 주", "This week", "今週") }
    var thisMonth: String { t("이번 달", "This month", "今月") }

    // MARK: 한도 섹션
    var limitsOfficial: String { t("한도 (공식)", "Limits (official)", "上限（公式）") }
    var fiveHourSession: String { t("5시간 세션", "5-hour session", "5時間セッション") }
    var weekly: String { t("주간", "Weekly", "週間") }
    var weeklyOpus: String { t("주간 Opus", "Weekly Opus", "週間 Opus") }
    var weeklySonnet: String { t("주간 Sonnet", "Weekly Sonnet", "週間 Sonnet") }
    var claudeCurrentBlock: String { t("Claude 현재 5h 블록", "Claude current 5h block", "Claude 現在の5hブロック") }
    var reset: String { t("리셋", "Reset", "リセット") }
    var limitReached: String { t("한도 도달", "Limit reached", "上限到達") }
    var personalSpendLimit: String { t("개인 사용 한도", "Personal spend limit", "個人利用上限") }
    var staleLimits: String { t("갱신 지연", "Stale", "更新遅延") }
    var refresh: String { t("갱신", "Refresh", "更新") }
    var limitsTapToLoad: String { t("공식 한도 불러오기", "Load official limits", "公式上限を読み込む") }

    /// 프로바이더 상태 페이지 인시던트 지표 → 현지화 라벨(표시 전용).
    func providerStatusLabel(_ indicator: ProviderStatusIndicator) -> String {
        switch indicator {
        case .operational: return t("정상", "Operational", "正常")
        case .minor:       return t("일부 장애", "Minor issues", "一部障害")
        case .major:       return t("장애", "Major outage", "障害")
        case .critical:    return t("심각한 장애", "Critical outage", "重大障害")
        case .maintenance: return t("점검 중", "Maintenance", "メンテナンス")
        case .unknown:     return t("상태 불명", "Status unknown", "状態不明")
        }
    }
    func plan(_ p: String) -> String { t("플랜 \(p)", "Plan \(p)", "プラン \(p)") }
    func limitsAccount(_ a: String) -> String { t("계정 \(a)", "Account \(a)", "アカウント \(a)") }

    // MARK: Additional Claude accounts (#327)
    var today: String { t("오늘", "Today", "今日") }
    func unattributedClaudeUsage(_ tokens: String) -> String {
        t("이번 달 계정 미확인: \(tokens)", "Not linked to an account this month: \(tokens)", "今月アカウント不明: \(tokens)")
    }
    var fiveHourNotStarted: String { t("다음 메시지부터 시작", "Starts with your next message", "次のメッセージから開始") }
    var sessionKeyDefaultAccountOnly: String {
        t("기본 Claude 계정(~/.claude)에만 적용됩니다.", "Applies to the default Claude account (~/.claude) only.",
          "デフォルトの Claude アカウント（~/.claude）にのみ適用されます。")
    }
    var additionalClaudeAccountsLabel: String { t("추가 Claude 계정", "Additional Claude accounts", "追加のClaudeアカウント") }
    var additionalClaudeAccountsHint: String {
        t("다른 Claude Code 로그인(CLAUDE_CONFIG_DIR)은 ~/.claude-* 폴더와 export 된 CLAUDE_CONFIG_DIR 에서 자동으로 찾습니다. 다른 위치의 설정 폴더만 여기 추가하세요(콤마·줄바꿈 구분). 공식 한도에 계정마다 탭이 생기며, 수동 갱신 때 폴더마다 Keychain 접근을 물을 수 있습니다.",
          "Other Claude Code logins (CLAUDE_CONFIG_DIR) are detected in ~/.claude-* folders and from an exported CLAUDE_CONFIG_DIR. Add config folders stored elsewhere here, comma/newline separated. Each account gets its own tab in the official limits; a manual refresh may ask for Keychain access for each folder.",
          "他のClaude Codeログイン(CLAUDE_CONFIG_DIR)は ~/.claude-* フォルダと、エクスポートされた CLAUDE_CONFIG_DIR から自動検出されます。別の場所にある設定フォルダだけをここに追加してください(カンマ・改行区切り)。公式上限にアカウントごとのタブが追加され、手動更新時にフォルダごとにKeychainへのアクセスを確認することがあります。")
    }
    func additionalClaudeAccountsDetected(_ folders: String) -> String {
        t("자동 감지: \(folders)", "Detected: \(folders)", "自動検出: \(folders)")
    }
    var trackedAccountLabel: String { t("추적할 Claude 계정", "Tracked Claude account", "追跡する Claude アカウント") }
    func trackedAccountToolTip(_ title: String) -> String {
        t("추적할 Claude 계정: \(title)", "Tracked Claude account: \(title)", "追跡する Claude アカウント: \(title)")
    }
    var trackedAccountHint: String {
        t("메뉴바 한도·5시간 예측의 기준이에요.",
          "Drives the menu bar limit and the 5h forecast.",
          "メニューバーの上限・5時間予測に使われます。")
    }
    var trackedAccountAutomatic: String { t("자동 (마지막 사용)", "Automatic (last used)", "自動（最後に使用）") }
    var trackedAccountHighest: String { t("사용률 최고", "Highest usage", "使用率が最大") }
    var additionalClaudeAccountsPlaceholder: String { t("~/.claude-work", "~/.claude-work", "~/.claude-work") }
    func additionalClaudeAccountsFound(_ n: Int) -> String {
        t("계정 폴더 \(n)개 찾음", "\(n) account folder(s) found", "アカウントフォルダが\(n)個見つかりました")
    }
    var sessionKeyPerAccountNote: String {
        t("기본 Claude 계정(~/.claude)에 적용됩니다. 다른 계정은 아래에서 각자 키를 넣을 수 있어요.",
          "Applies to the default Claude account (~/.claude). Each other account can have its own key below.",
          "デフォルトの Claude アカウント（~/.claude）に適用されます。ほかのアカウントは下でそれぞれキーを設定できます。")
    }
    /// An additional account's own key row: the account's tab title, or its folder before its limits load.
    func accountSessionKeyLabel(_ account: String) -> String {
        t("\(account) 세션 키", "Session key for \(account)", "\(account) のセッションキー")
    }
    func additionalAccountExpiredHint(_ folder: String) -> String {
        t("CLAUDE_CONFIG_DIR=\(folder) 로 Claude Code 를 한 번 실행한 뒤 다시 시도하세요.",
          "Run Claude Code once with CLAUDE_CONFIG_DIR=\(folder), then retry.",
          "CLAUDE_CONFIG_DIR=\(folder) で Claude Code を一度実行してから再試行してください。")
    }

    // MARK: claude.ai 세션 키 (Keychain 프롬프트 없는 한도 경로)
    var sessionKeyLabel: String { t("claude.ai 세션 키", "claude.ai session key", "claude.ai セッションキー") }
    var sessionKeyHint: String {
        t("Keychain 팝업 없이 공식 한도를 조회합니다. 브라우저 개발자도구 → Application → Cookies → claude.ai → sessionKey 값을 붙여넣으세요.",
          "Fetches official limits with no Keychain pop-up. Paste the value from DevTools → Application → Cookies → claude.ai → sessionKey.",
          "Keychain のポップアップなしで公式上限を取得します。開発者ツール → Application → Cookies → claude.ai → sessionKey の値を貼り付けてください。")
    }
    /// 평문 보관을 숨기지 않는다 — 사용자가 무엇을 맡기는지, 어떻게 취소하는지 알아야 한다.
    var sessionKeyStorageNote: String {
        t("키는 이 Mac 의 앱 폴더에 본인만 읽을 수 있는 파일로 저장됩니다(암호화 아님). 브라우저에서 로그아웃하면 즉시 무효화됩니다.",
          "The key is stored in this Mac's app folder as an owner-only file (not encrypted). Logging out in your browser invalidates it immediately.",
          "キーはこの Mac のアプリフォルダに本人のみ読み取り可能なファイルとして保存されます(暗号化なし)。ブラウザでログアウトすると即時無効になります。")
    }
    var sessionKeySaved: String { t("설정됨", "Saved", "設定済み") }
    var save: String { t("저장", "Save", "保存") }
    var delete: String { t("삭제", "Delete", "削除") }
    var sessionKeyOrganizationLabel: String { t("조직", "Organization", "組織") }
    var sessionKeyMalformedError: String {
        t("세션 키 형식이 아닙니다. sessionKey 쿠키 값 전체를 붙여넣었는지 확인하세요(sk-ant- 로 시작).",
          "That isn't a session key. Check you pasted the whole sessionKey cookie value (starts with sk-ant-).",
          "セッションキーの形式ではありません。sessionKey クッキーの値全体を貼り付けたか確認してください(sk-ant- で始まります)。")
    }
    var sessionKeyExpiredError: String {
        t("세션 키가 만료됐습니다. 브라우저에서 다시 복사해 붙여넣으세요.",
          "The session key expired. Copy a fresh one from your browser and paste it again.",
          "セッションキーの有効期限が切れました。ブラウザから再度コピーして貼り付けてください。")
    }
    var sessionKeyNoOrgError: String {
        t("이 키로 한도를 볼 수 있는 조직이 없습니다.",
          "No organization on this key can show limits.",
          "このキーで上限を確認できる組織がありません。")
    }

    // MARK: 세션 키 만료 안내 — OAuth 만료와 처방이 다르므로 문구·행동을 따로 둔다
    var sessionKeyExpiredTitle: String {
        t("claude.ai 세션 키 만료 — 한도가 갱신 안 돼요",
          "claude.ai session key expired — limits aren't refreshing",
          "claude.ai セッションキーの期限切れ — 上限が更新されません")
    }
    /// Keychain 재조회를 권하지 않는다 — 세션 키가 죽은 상태에서 그건 아무것도 고치지 못하고,
    /// 하필 세션 키로 피하려던 그 팝업을 띄운다.
    var sessionKeyExpiredNoticeHint: String {
        t("표시된 값은 만료 전 기준이에요. 브라우저에서 sessionKey 를 다시 복사해 설정 → 고급에 붙여넣으세요.",
          "The numbers shown are from before it expired. Copy a fresh sessionKey from your browser and paste it under Settings → Advanced.",
          "表示中の値は期限切れ前のものです。ブラウザから sessionKey を再度コピーし、設定 → 詳細に貼り付けてください。")
    }
    var sessionKeyExpiredBadge: String {
        t("만료됨", "Expired", "期限切れ")
    }

    // MARK: Claude Keychain 항상 허용 초기화 도움말 (상시 안내)
    var claudeKeychainHelpTitle: String {
        t("왜 주기적으로 암호를 묻나요?",
          "Why does it ask for password periodically?",
          "なぜ定期的にパスワードを求められるのですか？")
    }
    var claudeKeychainHelpBody: String {
        t("Claude CLI가 백그라운드에서 토큰을 교체할 때 macOS 키체인의 '항상 허용' 권한이 초기화됩니다. 세션 키를 등록하면 암호 입력 없이 백그라운드 자동 갱신이 유지됩니다.",
          "When Claude CLI rotates tokens in the background, macOS resets the Keychain 'Always Allow' permission. Registering a session key keeps background limits refreshed without any password prompt.",
          "Claude CLI がバックグラウンドでトークンをローテーションすると、macOS Keychain の「常に許可」権限がリセットされます。セッションキーを登録すると、パスワード入力なしで自動更新が維持されます。")
    }
    var registerSessionKey: String {
        t("세션 키 등록", "Register Session Key", "セッションキーを登録")
    }
    var claudeKeychainHelpTooltip: String {
        t("Claude 키체인 인증 안내",
          "Claude Keychain authentication info",
          "Claude Keychain 認証について")
    }
    func forecastReach(_ time: String) -> String {
        t("현재 속도면 \(time) 한도 도달", "At current rate, limit hit at \(time)", "現在のペースで \(time) に上限到達")
    }
    var forecastNoReach: String {
        t("현재 속도로는 리셋 전 한도 도달 없음", "Won't hit limit before reset at current rate", "現在のペースではリセット前に上限到達なし")
    }

    /// Claude oauth/usage 신형 limits[] 엔트리 이름 — kind + 모델 스코프 기반.
    func claudeLimitEntry(kind: String?, model: String?) -> String {
        switch kind {
        case "session": return fiveHourSession
        case "weekly_all": return weekly
        case "weekly_scoped":
            // 모델명이 없으면 레거시 "주간" 행과 이름이 겹치므로 scoped 임을 구분 표기
            guard let model else { return t("주간 (모델별)", "Weekly (scoped)", "週間（モデル別）") }
            return t("주간 \(model)", "Weekly \(model)", "週間 \(model)")
        default:
            let base = kind ?? "limit"
            let name = model.map { " \($0)" } ?? ""
            return base.replacingOccurrences(of: "_", with: " ") + name
        }
    }

    /// Codex 한도 윈도우 이름 (windowDurationMins 기반). 알림·팝오버 공통.
    func codexWindow(_ mins: Int?) -> String {
        switch mins {
        case 300: return fiveHourSession
        case 10_080: return weekly
        case let m? where m >= 60 && m % 60 == 0:
            let h = m / 60
            return t("\(h)시간", "\(h)h", "\(h)時間")
        case let m?: return t("\(m)분", "\(m)m", "\(m)分")
        case nil: return t("한도", "Limit", "上限")
        }
    }

    // MARK: 푸터
    var refreshNow: String { t("지금 새로고침", "Refresh now", "今すぐ更新") }
    var updated: String { t("갱신", "Updated", "更新") }
    var settings: String { t("설정", "Settings", "設定") }
    var back: String { t("뒤로", "Back", "戻る") }
    var generalSectionTitle: String { t("일반", "General", "一般") }
    var menuBarSectionTitle: String { t("메뉴바에 표시", "Show in menu bar", "メニューバーに表示") }
    var advancedSectionTitle: String { t("고급", "Advanced", "詳細") }
    var advancedDisclosureLabel: String { t("고급 설정 · 진단", "Advanced · diagnostics", "詳細設定・診断") }
    var aboutSupportSectionTitle: String { t("정보 & 지원", "About & Support", "情報とサポート") }
    var quit: String { t("종료", "Quit", "終了") }

    // MARK: 설정
    var refreshInterval: String { t("새로고침 간격", "Refresh interval", "更新間隔") }
    var language: String { t("언어", "Language", "言語") }
    var menuBarItems: String { t("메뉴바 표시 항목 (복수 선택)", "Menu bar items (multi-select)", "メニューバー表示項目（複数選択）") }
    var todayTokensShort: String { t("오늘 토큰", "Today's tokens", "本日のトークン") }
    /// **실제 지출이 아니라 API 환산**이다. 정액제(Claude Max·ChatGPT 구독) 사용자에게 토큰 단가를
    /// 곱한 금액을 "쓴 돈"이라 부르면 안 나간 돈을 나갔다고 말하는 셈이라, 이름을 환산으로 둔다.
    var todayCost: String { t("오늘 API 환산 ($)", "Today's API equivalent ($)", "本日のAPI換算 ($)") }
    var limitPercent: String { t("한도 %", "Limit %", "上限 %") }
    /// 일별 추이 막대 행의 제목. 범위가 "이번 달"임을 문구에 담는다 — 롤링 30일로 읽히면 안 된다.
    /// 페이스 대비 단계 이름. paceHint 와 같은 이유로 "적정"처럼 규범적인 말은 피하고
    /// 소진 속도만 묘사한다.
    func paceTier(_ tier: PaceTier) -> String {
        switch tier {
        case .wayUnder: return t("여유 많음", "Well under pace", "かなり余裕")
        case .under: return t("여유", "Under pace", "余裕あり")
        case .onPace: return t("페이스대로", "On pace", "ペース通り")
        case .slightlyOver: return t("조금 빠름", "Slightly fast", "やや速い")
        case .over: return t("빠름", "Fast", "速い")
        case .wayOver: return t("매우 빠름", "Very fast", "とても速い")
        }
    }
    /// 페이스 대비 차이(%p). **쓴 양**으로 말한다 — "앞섬/위" 같은 위치 표현은 잔량 모드에서
    /// 채움이 마커보다 짧게 그려질 때 방향이 반대로 읽힌다(#286 부류). 0 이면 문구 없음.
    /// 유럽어는 단계 이름("Under pace")이 이미 "페이스"를 말하므로 여기선 반복하지 않는다.
    func paceDelta(_ points: Int) -> String? {
        if points > 0 {
            return t("페이스보다 \(points)%p 더 씀", "\(points) pts more used", "ペースより\(points)pt多く使用")
        }
        if points < 0 {
            let n = -points
            return t("페이스보다 \(n)%p 덜 씀", "\(n) pts less used", "ペースより\(n)pt少なく使用")
        }
        return nil
    }
    /// 페이스 눈금 툴팁. "적정 사용량"으로 부르지 않는다 — 권고가 아니라 "이 속도면 리셋 전에
    /// 소진된다"는 기준선이다.
    func paceHint(_ percent: String) -> String {
        t("페이스 — 창 시간만큼 균등하게 썼다면 지금 \(percent)입니다.",
          "Pace — an even burn across this window would sit at \(percent) now.",
          "ペース — この枠を均等に使っていれば今は \(percent) です。")
    }

    // MARK: Usage recap
    var recapOpen: String { t("사용량 돌아보기", "Usage recap", "使用量のふりかえり") }
    var recapTokensUnit: String { t("토큰", "tokens", "トークン") }
    func recapScopeName(_ scope: RecapScope) -> String {
        switch scope {
        case .week: t("주간", "Week", "週")
        case .month: t("월간", "Month", "月")
        case .year: t("연간", "Year", "年")
        }
    }
    /// Shown under a running period, whose chip compares the same number of days.
    func recapCompareSoFar(_ scope: RecapScope) -> String {
        switch scope {
        case .week: t("지난주 같은 기간과 비교", "Compared with the same days last week", "先週の同じ期間と比較")
        case .month: t("지난달 같은 기간과 비교", "Compared with the same days last month", "先月の同じ期間と比較")
        case .year: t("작년 같은 기간과 비교", "Compared with the same days last year", "昨年の同じ期間と比較")
        }
    }
    func recapCurrentPeriod(_ scope: RecapScope) -> String {
        switch scope {
        case .week: thisWeek
        case .month: thisMonth
        case .year: t("올해", "This year", "今年")
        }
    }
    var recapPrevious: String { t("이전", "Previous", "前へ") }
    var recapNext: String { t("다음", "Next", "次へ") }
    var recapBestDay: String { t("최고의 날", "Best day", "最高の日") }
    var recapActiveDays: String { t("활동한 날", "Active days", "稼働日") }
    var recapBestStreak: String { t("최장 연속", "Best streak", "最長連続") }
    var recapHatched: String { t("부화", "Hatched", "ふか") }
    var recapNoData: String { t("기록 없음", "no data", "記録なし") }
    func recapDays(_ count: Int) -> String {
        t("\(count)일", "\(count)d", "\(count)日")
    }
    func recapBestDayLine(_ day: String, _ tokens: String) -> String {
        t("최고의 날은 \(day) — \(tokens) 토큰.", "Your best day was \(day) — \(tokens) tokens.", "最高の日は \(day)、\(tokens) トークン。")
    }
    var recapNoGraduates: String {
        t("이 기간에 졸업한 포켓몬이 없어요.", "No graduation in this period.", "この期間の卒業はありません。")
    }

    var costUnavailable: String { t("계산 불가", "Unavailable", "計算不可") }
    var costEstimateHint: String { t("모델 단가로 환산한 추정 비용입니다. 구독료나 실제 청구액이 아닙니다.", "Estimated from model token rates; not a subscription fee or invoice.", "モデル単価による推定です。購読料や実際の請求額ではありません。") }
    var costReportedHint: String { t("도구가 기록한 비용입니다. 실제 청구액과 다를 수 있습니다.", "Cost recorded by the tool; it may differ from the actual bill.", "ツールが記録したコストです。実際の請求額とは異なる場合があります。") }
    var costUnavailableHint: String { t("비용 기록이나 확인된 단가·토큰 구분이 없어 계산할 수 없습니다.", "No usable cost record or verified model rate and token breakdown is available.", "コスト記録、確認済み単価、またはトークン内訳がないため計算できません。") }
    var costPartialHint: String { t("일부 사용량은 계산할 수 없어 제외했습니다. 표시 금액은 계산 가능한 부분의 합계이며 청구액이 아닙니다.", "Some usage could not be priced and is excluded. This is the known portion, not an invoice.", "計算できない使用量を除いた部分合計です。請求額ではありません。") }
    var dailyTrend: String { t("이번 달 일별", "Daily this month", "今月の日別") }
    /// 추이의 최댓값 라벨 — 막대 높이가 상대값이라 절대 스케일을 한 군데는 적어줘야 한다.
    var peakDay: String { t("최다", "Peak", "最多") }
    var menuLimitColor: String {
        t("퍼센트 색상", "Percent color", "パーセントの色")
    }
    var menuLimitColorHint: String {
        t("팝오버 한도 게이지와 같은 색", "Same colors as the popover limit gauges", "ポップオーバーの上限ゲージと同じ色")
    }
    func menuLimitColorMode(_ mode: UsageStore.MenuLimitColorMode) -> String {
        switch mode {
        case .gauge:
            return t("게이지와 같게", "Match gauges", "ゲージと同じ")
        case .attention:
            return t("주의 단계만", "Only when fast", "速いときだけ")
        case .off:
            return t("끔", "Off", "オフ")
        }
    }
    var limitDisplayModeLabel: String { t("한도 표시 방식", "Limit display", "上限の表示") }
    var limitDisplayUsed: String { t("사용량", "Used", "使用量") }
    var limitDisplayRemaining: String { t("남은 양", "Remaining", "残量") }
    /// 팝오버 한도 행의 remaining 모드 표시 — %에 자기설명 접미사를 붙인다.
    func percentRemaining(_ percent: String) -> String {
        t("\(percent) 남음", "\(percent) left", "残り\(percent)")
    }
    var allOffHint: String { t("전부 끄면 캐릭터만 보여요", "All off shows only the character", "すべてオフにするとキャラクターのみ表示") }
    // MARK: 플로팅 펫
    var floatingPetSectionTitle: String { t("플로팅 펫", "Floating Pet", "フローティングペット") }
    var floatingPetEnableLabel: String { t("플로팅 펫 표시", "Show floating pet", "フローティングペットを表示") }
    var floatingPetHideLabel: String { t("플로팅 펫 숨기기", "Hide floating pet", "フローティングペットを隠す") }
    var floatingPetHint: String {
        t("포켓몬이 화면 위에 떠 있어요 — 드래그로 위치를 옮길 수 있어요",
          "Your Pokémon floats over the screen — drag to reposition",
          "ポケモンが画面の上に浮かびます — ドラッグで移動できます")
    }
    var floatingPetHomeLabel: String { t("처음 자리로", "Bring it back", "はじめの場所へ") }
    var floatingPetHomeHint: String {
        t("펫이 안 보이면 화면 오른쪽 아래로 돌려보내요",
          "If you can't find the pet, send it to the bottom-right of the screen",
          "ペットが見当たらないとき、画面の右下へ戻します")
    }
    var floatingPetHomeButton: String { t("돌려보내기", "Reset", "戻す") }
    var floatingPetSizeLabel: String { t("크기", "Size", "サイズ") }
    /// 지금은 한도 알림만 말풍선으로 뜨지만, 알림 종류가 늘어도 이 라벨은 그대로 쓴다.
    var floatingPetBubbleAlertsLabel: String {
        t("말풍선으로 알림 받기", "Show notifications as bubbles", "通知を吹き出しで表示")
    }
    var floatingPetBurnSpeedLabel: String {
        t("바쁠수록 빠르게", "Speed up when busy", "忙しいほど速く")
    }
    /// 배수를 적지 않는다 — 사다리(`PetSpeed.ladder`)가 바뀌면 문구가 조용히 거짓말이 된다.
    var floatingPetBurnSpeedHint: String {
        t("토큰을 많이 쓰는 동안 펫이 더 빨리 움직여요 — 쉬는 동안엔 원래 속도예요",
          "Your pet moves faster while you're burning tokens, and idles at its normal speed",
          "トークンを多く使っている間はペットが速く動き、休んでいる間は元の速さになります")
    }
    /// 설정의 박스 섹션 — 보관함 칸을 어떻게 그릴지. 박스 전용 설정만 들어간다.
    var boxSectionTitle: String { t("박스", "Box", "ボックス") }
    var fillBoxSlotsLabel: String {
        t("칸에 꽉 채우기", "Fill the slot", "マスいっぱいに")
    }
    var antialiasLabel: String {
        t("스프라이트 부드럽게", "Smooth sprites", "スプライトを滑らかに")
    }
    var floatingPetMenuOpen: String { t("토큰 바 열기", "Open Token Bar", "トークンバーを開く") }
    var floatingPetMenuHide: String {
        t("플로팅 펫 끄기", "Turn off floating pet", "フローティングペットをオフ")
    }
    func floatingPetHoverTokensOnly(_ tokens: String) -> String {
        t("오늘 \(tokens) 토큰", "Today: \(tokens) tokens", "今日: \(tokens) トークン")
    }
    func floatingPetHoverWithLimit(_ tokens: String, _ percent: String) -> String {
        t("오늘 \(tokens) 토큰 (한도 \(percent))",
          "Today: \(tokens) tokens (limit \(percent))",
          "今日: \(tokens) トークン（上限 \(percent)）")
    }

    var disableKeychain: String { t("Keychain 접근 끄기", "Disable Keychain access", "Keychainアクセスを無効化") }
    var disableKeychainHint: String { t("켜면 Keychain 접근 허용 팝업이 더 안 떠요 — 공식 한도(%)만 숨겨지고 토큰·비용은 그대로", "When on, no more Keychain permission pop-ups — only official limits (%) are hidden; tokens/cost stay", "オンにするとKeychain許可のポップアップが出なくなります — 公式上限(%)のみ非表示、トークン・費用はそのまま") }
    var refreshLimitToken: String { t("한도 토큰 캐시 갱신", "Refresh limit token cache", "上限トークンキャッシュを更新") }
    var onlyOnPress: String { t("누를 때만 Keychain 을 읽어요 — 자동 폴링은 안 읽어 팝업이 안 떠요. 토큰 만료 후 이 버튼으로 한도 갱신", "Reads Keychain only when pressed — auto-polling never does, so no pop-ups. Refresh limits here after the token expires", "押した時のみKeychainを読みます — 自動更新では読まずポップアップも出ません。トークン期限切れ後はこのボタンで上限を更新") }
    var launchAtLogin: String { t("로그인 시 자동 시작", "Launch at login", "ログイン時に自動起動") }
    var bundledOnly: String { t(".app 번들로 설치된 경우에만 사용 가능 (scripts/build-app.sh)", "Available only when installed as an .app bundle (scripts/build-app.sh)", ".appバンドルでインストールした場合のみ利用可能 (scripts/build-app.sh)") }
    var notificationsSection: String { t("알림", "Notifications", "通知") }
    var limitNotificationsLabel: String { t("한도 알림", "Limit alerts", "上限通知") }
    var statusChecksLabel: String { t("프로바이더 상태 확인", "Provider status checks", "プロバイダー状態チェック") }
    var statusChecksHint: String { t("Claude·OpenAI 장애를 팝오버에 표시 (알림 아님)", "Show Claude / OpenAI incidents in the popover (not a notification)", "Claude・OpenAIの障害をポップオーバーに表示（通知ではない）") }
    var warning: String { t("경고", "Warning", "警告") }
    var critical: String { t("임박", "Critical", "切迫") }
    var aggregationNote: String { t("토큰 집계 기준: totalTokens (input + output + cache, 로컬 날짜)", "Token basis: totalTokens (input + output + cache, local date)", "集計基準: totalTokens (input + output + cache, ローカル日付)") }
    var close: String { t("닫기", "Close", "閉じる") }

    // MARK: 문제 제보 (설정 → GitHub 이슈)
    var reportProblem: String { t("문제 제보", "Report a problem", "問題を報告") }
    var showLogFile: String { t("로그 파일 보기", "Show log file", "ログファイルを表示") }
    var reportOnGitHub: String { t("GitHub", "GitHub", "GitHub") }
    /// **짧게 유지한다.** "진단 정보 복사"/"Copy diagnostics" 로 뒀더니 GitHub 버튼과 한 줄에
    /// 들어가면서 잘렸고(`assets/settings.png` 에서 "Copy diagno…"), 왼쪽 설명이 6줄 기둥으로
    /// 접혔다. 옆 문장이 이미 무엇을 복사하는지 말한다.
    var copyDiagnostics: String { t("복사", "Copy", "コピー") }
    var diagnosticsCopied: String { t("복사됨", "Copied", "コピー済") }
    var reportAttachHint: String {
        t("앱 버전·macOS·직전 크래시 기록이 함께 담겨요. 보내기 전에 내용을 확인하실 수 있어요.",
          "Includes app version, macOS, and the last crash record. You can review it before sending.",
          "アプリのバージョン・macOS・直前のクラッシュ記録が含まれます。送信前に内容を確認できます。")
    }
    func reportIssueTitle(_ version: String) -> String {
        t("[v\(version)] 문제 리포트", "[v\(version)] Problem report", "[v\(version)] 問題レポート")
    }
    func reportBrowserFallback(_ url: String) -> String {
        t("브라우저를 열 수 없어요. 이 주소로 들어가 주세요: \(url)",
          "Couldn't open a browser. Please visit: \(url)",
          "ブラウザを開けません。こちらへアクセスしてください: \(url)")
    }

    // MARK: 크래시 배너 (홈 탭)
    var crashCardTitle: String {
        t("직전에 예기치 않게 종료됐어요",
          "The app closed unexpectedly last time",
          "前回、予期せず終了しました")
    }
    var crashCardBody: String {
        t("무엇을 하던 중이었는지 기록해 뒀어요. 제보해 주시면 고치는 데 큰 도움이 돼요.",
          "We saved what the app was doing. Reporting it helps a lot with a fix.",
          "何をしていたかを記録しました。ご報告いただけると修正に大きく役立ちます。")
    }
    var crashCardReport: String { t("제보하기", "Report", "報告する") }

    /// 새로고침 간격 라벨 (초 단위 값 → 표시). 0 = 수동.
    func intervalLabel(_ seconds: TimeInterval) -> String {
        if seconds == 0 { return t("수동", "Manual", "手動") }
        let m = Int(seconds / 60)
        return t("\(m)분", "\(m) min", "\(m)分")
    }

    // MARK: 진화 라인 뷰 (EvoLineView — 박스/도감 재사용 대비)
    var unknownNextEvolution: String { t("알 수 없는 다음 진화", "Unknown next evolution", "次の進化先は不明") }

    // MARK: Claude 한도 토큰 갱신 오류 (친절 안내)
    func limitRefreshHTTPError(_ status: Int) -> String {
        if status == 401 || status == 403 {
            return t(
                "Claude 자격증명이 만료됐거나 권한이 없어요 (\(status)). Claude Code 로그인을 확인하세요. Codex만 쓴다면 무시해도 돼요 — Codex 한도는 따로 보여요.",
                "Claude credential is expired or unauthorized (\(status)). Check that you're signed in to Claude Code. If you only use Codex you can ignore this — Codex limits show separately.",
                "Claude の認証情報が期限切れか権限がありません (\(status))。Claude Code にサインインしているか確認してください。Codex のみ使用する場合は無視できます — Codex の上限は別に表示されます。")
        }
        return t("Claude 한도 조회 실패 (\(status)).", "Failed to fetch Claude limits (\(status)).", "Claude の上限取得に失敗しました (\(status))。")
    }
    var limitRefreshNoCredential: String {
        t("Claude 자격증명을 찾지 못했어요. Claude Code 에 로그인하면 한도가 보여요. Codex만 쓴다면 무시해도 돼요.",
          "No Claude credential found. Sign in to Claude Code to see limits. If you only use Codex you can ignore this.",
          "Claude の認証情報が見つかりません。Claude Code にサインインすると上限が表示されます。Codex のみなら無視して構いません。")
    }
    var limitRefreshReauthNeeded: String {
        t("Claude 자격증명에 계정 로그인 정보가 없어요. Claude Code 에서 `/login` 으로 다시 로그인하면 한도가 표시됩니다.",
          "Your Claude credential has no account sign-in. Run `/login` in Claude Code to sign in again and limits will appear.",
          "Claude の認証情報にアカウントのサインインが含まれていません。Claude Code で `/login` を実行して再度サインインすると上限が表示されます。")
    }
    var limitRefreshGeneric: String {
        t("Claude 한도 조회에 실패했어요. 잠시 후 다시 시도하세요.",
          "Couldn't fetch Claude limits. Please try again shortly.",
          "Claude の上限取得に失敗しました。しばらくして再試行してください。")
    }
    var limitRefreshRateLimited: String {
        t("Claude 한도 조회가 일시 제한됐어요 (429). 잠시 쉬었다가 자동으로 다시 시도해요.",
          "Claude limit checks are temporarily rate-limited (429). Backing off and retrying automatically.",
          "Claude の上限取得が一時的に制限されています (429)。少し待って自動的に再試行します。")
    }

    // MARK: Claude 세션 만료(401) 안내
    var claudeAuthExpiredTitle: String {
        t("Claude 세션 만료 — 한도가 갱신 안 돼요",
          "Claude session expired — limits can't refresh",
          "Claude セッション期限切れ — 上限を更新できません")
    }
    var claudeAuthExpiredHint: String {
        t("표시된 값은 만료 전 기준이에요. 다시 시도하거나, Claude Code 를 한 번 실행하면 자동으로 갱신돼요.",
          "Values shown are from before expiry. Retry, or run Claude Code once to refresh automatically.",
          "表示値は期限切れ前のものです。再試行するか、Claude Code を一度実行すると自動更新されます。")
    }
    var retry: String { t("다시 시도", "Retry", "再試行") }

    // MARK: 업데이트 알림
    func updateAvailable(_ version: String, current: String) -> String {
        t("🆕 v\(version) 사용 가능 (현재 \(current))",
          "🆕 v\(version) available (you have \(current))",
          "🆕 v\(version) が利用可能（現在 \(current)）")
    }
    var updateButton: String { t("업데이트", "Update", "更新") }
    /// 예전 라벨은 "나중에"였지만 실제로는 그 버전을 영구히 건너뛰었다 — 하는 일대로 부른다(업스트림 #311).
    var skipThisVersion: String { t("이 버전 건너뛰기", "Skip this version", "このバージョンをスキップ") }
    func skippedVersion(_ version: String) -> String {
        t("v\(version)\(Josa.eulReul(version)) 건너뛰었어요",
          "You skipped v\(version)",
          "v\(version) をスキップしました")
    }
    var showSkippedAgain: String { t("다시 알리기", "Show again", "もう一度表示") }
    var updating: String { t("업데이트 중…", "Updating…", "更新中…") }
    var updateSectionTitle: String { t("업데이트", "Updates", "アップデート") }
    var updateNotificationsLabel: String { t("업데이트 알림", "Update notifications", "アップデート通知") }
    var checkForUpdatesLabel: String { t("업데이트 확인", "Check for updates", "アップデートを確認") }
    var checkNowButton: String { t("지금 확인", "Check now", "今すぐ確認") }
    func updateFound(_ version: String) -> String { t("새 버전 v\(version) 있어요", "Version \(version) is available", "バージョン \(version) が利用可能です") }
    func upToDate(_ version: String) -> String { t("최신 버전이에요 (v\(version))", "You're on the latest (v\(version))", "最新です (v\(version))") }

    // MARK: 알림
    var notifCritical: String { t("한도 임박", "Limit imminent", "上限切迫") }
    var notifWarning: String { t("한도 경고", "Limit warning", "上限警告") }
    func notifBody(_ name: String, _ percent: String) -> String {
        t("\(name) 한도 \(percent) 사용", "\(name) at \(percent)", "\(name) 上限 \(percent) 使用")
    }
    var claudeFiveHour: String { t("Claude 5시간 세션", "Claude 5-hour session", "Claude 5時間セッション") }
    var claudeWeekly: String { t("Claude 주간", "Claude weekly", "Claude 週間") }
    var codexPersonalLimit: String { t("Codex 개인 한도", "Codex personal limit", "Codex 個人上限") }

    // MARK: 부화 알림
    var notifHatchTitle: String { t("알이 부화했어요", "An egg hatched", "タマゴがふ化しました") }
    /// 하나만 깼을 때 — 어떤 종인지 짚어준다.
    func notifHatchSingleBody(_ speciesID: Int, shiny: Bool) -> String {
        let mark = shiny ? "✨ " : ""
        return t("\(mark)#\(speciesID) 를 만났어요", "\(mark)You met #\(speciesID)", "\(mark)#\(speciesID) に出会いました")
    }
    /// 여러 개가 한꺼번에 깼을 때 — 하나로 묶는다(알림 폭탄 방지). 이로치가 섞였으면 개수를 곁들인다.
    func notifHatchMultipleBody(_ count: Int, shinyCount: Int) -> String {
        let ko = shinyCount > 0 ? " (✨ \(shinyCount)마리)" : ""
        let en = shinyCount > 0 ? " (✨ \(shinyCount) shiny)" : ""
        let ja = shinyCount > 0 ? " (✨ \(shinyCount)匹)" : ""
        return t("\(count)마리가 부화했어요\(ko)", "\(count) hatched\(en)", "\(count)匹がふ化しました\(ja)")
    }

    // MARK: 위장이 풀릴 때
    var notifDisguiseTitle: String { t("정체가 드러났어요", "It was not what it seemed", "正体があらわれました") }
    /// 무엇이었는지 짚어준다 — 정체가 이 연출의 전부라 문구가 애매하면 놓친 것과 같다.
    func notifDisguiseBody(_ was: Int, shiny: Bool) -> String {
        let mark = shiny ? "✨ " : ""
        return t("\(mark)곁에 있던 아이는 #\(was) 이었어요",
                 "\(mark)The one at your side was #\(was)",
                 "\(mark)そばにいたのは #\(was) でした")
    }
    /// 둘 이상이 한꺼번에 풀렸을 때 — 알림을 하나로 묶는다(부화 알림과 같은 규칙).
    func notifDisguiseMultipleBody(_ count: Int) -> String {
        t("\(count)마리의 정체가 드러났어요", "\(count) of them were not what they seemed",
          "\(count)匹の正体があらわれました")
    }
}
