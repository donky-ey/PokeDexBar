import AppKit
import SwiftUI

enum PopoverTab { case home, box, collection, bag, shop }

/// 팝오버 치수의 단일 소스. 자식이 쓸 수 있는 폭을 알아야 할 때 이 값을 쓴다 — 넘치는 자식이
/// 부모 폭을 부풀리므로 GeometryReader 로 재면 순환한다.
enum PopoverMetrics {
    static let width: CGFloat = 360
    static let padding: CGFloat = 14
    /// 이 폭을 넘는 자식은 팝오버 창에 좌우로 잘린다.
    static let contentWidth: CGFloat = width - padding * 2
}

/// 팝오버 내부 내비게이션 상태(현재 탭 / 설정 표시 여부).
/// NSHostingController 는 팝오버를 닫아도 재사용되어 @State 가 유지되므로, 화면 상태를 이
/// Observable 로 분리해 AppDelegate 가 팝오버를 열 때마다 reset() 한다 — 닫혔다 열리면 항상 Home.
@MainActor
@Observable
final class PopoverNavigation {
    var showSettings = false
    var tab: PopoverTab = .home
    /// 프로바이더 탭 선택 — reset() 대상이 아님(팝오버를 다시 열어도 보던 서비스 유지).
    var providerID: String?

    func reset() {
        showSettings = false
        tab = .home
    }
}

struct PopoverView: View {
    @Environment(UsageStore.self) private var store
    @Environment(UpdateChecker.self) private var updater
    @Environment(PopoverNavigation.self) private var nav

    let player: PlayerStore
    let provider: any PokeProviding

    /// 박스가 진화 후보를 보여주려면 라인이 필요하다. 개체 baseID → 라인, 로드되면 채운다.
    @State private var evoLines: [Int: EvoLine] = [:]
    /// 지금 fetch 중인 baseID — 같은 종 개체가 여럿(박스의 핵심 시나리오) 화면에 뜨면 각 행의
    /// 쓰다듬기 — 누르기 시작한 시각과 하트 표시. 저장하지 않는 화면 상태다.
    @State private var pettingSince: Date?
    @State private var showHeart = false
    @State private var heartRise: CGFloat = 0
    @State private var heartOpacity: Double = 0
    /// `.task` 가 동시에 `loadLine` 을 부르므로, 완료 전 상태(로딩 중)도 별도로 추적해야 한다.
    /// `evoLines` 만으로는 진행 중인 fetch 를 못 봐서(아직 키가 없으니) 중복 fetch 가 생긴다.
    @State private var loadingLines: Set<Int> = []
    /// 박스에서 상세를 열어 둔 개체. 여기서 들고 있어야 탭을 옮기면 상세가 닫힌다 —
    /// 박스 안에 두면 도감에 갔다 돌아왔을 때 옛 개체 상세가 그대로 남는다.
    @State private var boxSelection: UUID?

    private var l: L { player.l }

    /// 스타터를 아직 안 골랐나 — 골라야 다른 화면을 쓸 수 있다. 순수 판정이라 테스트로 잠근다.
    nonisolated static func needsStarter(_ state: PlayerState) -> Bool { !state.starterChosen }

    /// 라인 fetch 를 새로 시작해야 하나 — 이미 로드됐거나(`loadedIDs`) 이미 진행 중이면(`loadingIDs`)
    /// false. 순수 판정이라 테스트로 잠근다(같은 종 여럿이 동시에 화면에 뜨는 게 박스의 정상 시나리오라
    /// 중복 fetch 로 새는 걸 여기서 막는다).
    nonisolated static func shouldStartLoadingLine(_ baseID: Int, loadedIDs: Set<Int>, loadingIDs: Set<Int>) -> Bool {
        !loadedIDs.contains(baseID) && !loadingIDs.contains(baseID)
    }

    /// 1초 카운트다운 틱(TimelineView)을 걸어야 하나 — 부화 중인 알이 있을 때만.
    /// 알을 한 번도 안 뽑은 사용자에게 매초 재렌더를 시키지 않는다. 순수 판정이라 테스트로 잠근다.
    nonisolated static func needsCountdownTick(_ state: PlayerState) -> Bool { !state.eggs.isEmpty }

    /// 위장이 풀리는 걸 **보고 있는 그 자리에서** 보이게 하려면 틱이 필요하다. 사용량 틱만으로는
    /// 새로고침 간격만큼(수 분) 늦게 바뀌어, 10분을 세고 기다린 사용자가 아무 일도 안 일어난다고
    /// 느낀다. 위장한 개체가 파트너일 때만 건다 — 그때만 시간이 흐르므로 다른 경우엔 켤 이유가 없다.
    nonisolated static func needsDisguiseTick(_ state: PlayerState) -> Bool {
        state.partner?.disguisedAs != nil
    }

    var body: some View {
        Group {
            if Self.needsStarter(player.state) {
                StarterPickerView(store: player, provider: provider) { }
            } else {
                existingBody
            }
        }
    }

    private var existingBody: some View {
        // NOTE: 설정을 .sheet 로 띄우면 transient 팝오버가 닫힐 때 시트가 고아로 남아
        // 이후 팝오버의 모든 버튼 클릭을 차단할 수 있음 — 팝오버 내부 화면 전환으로 처리
        @Bindable var nav = nav
        return Group {
            if nav.showSettings {
                SettingsView(onClose: { nav.showSettings = false })
                    .environment(store)
                    .environment(player)
                    .environment(updater)
            } else {
                mainContent
            }
        }
        .frame(width: PopoverMetrics.width)
        // **성별 보정은 팝오버가 열릴 때마다 여기서 돈다.** 처음엔 상점 탭의 박사 구역에
        // 얹어 뒀는데, 그 탭을 한 번도 안 열면 영영 안 돌았다 — 박스로 바로 가는 사람은
        // 성별이 계속 안 보였다(사용자 지적). 마이그레이션을 특정 탭의 화면에 매달면 안 된다.
        // 인덱스는 디스크에 30일 캐시되므로 매번 열려도 네트워크를 안 탄다. 이미 다 채워져
        // 있으면 `backfillGenders` 가 아무것도 안 하고 돌아온다(멱등).
        .task {
            guard let index = try? await provider.baseSpeciesIndex(), !index.isEmpty else { return }
            player.backfillGenders(from: index)
        }
    }

    @ViewBuilder
    private var updateBanner: some View {
        if let update = updater.available, store.updateNotificationsEnabled {
            HStack(spacing: 8) {
                Text(l.updateAvailable(update.version, current: updater.currentVersion))
                    .font(.caption)
                Spacer()
                if updater.isUpdating {
                    Text(l.updating).font(.caption2).foregroundStyle(.secondary)
                    ProgressView().controlSize(.small)
                } else {
                    Button(l.updateButton) { updater.applyUpdate() }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                    Button(l.updateLater) { updater.skipCurrent() }
                        .buttonStyle(.borderless).controlSize(.small).foregroundStyle(.secondary)
                }
            }
            .padding(8)
            .background(Color.accentColor.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    /// 종 번호 → 현지화 이름. 라인은 베이스 종으로 캐시돼 있어 진화한 종은 키로 못 찾는다.
    /// 못 찾으면 nil — 부르는 쪽이 #번호로 떨어뜨린다.
    static func speciesName(_ speciesID: Int, in lines: [Int: EvoLine],
                            _ lang: AppLanguage) -> String? {
        for line in lines.values where line.tree.node(withID: speciesID) != nil {
            return line.localizedName(speciesID, lang)
        }
        return nil
    }

    private var mainContent: some View {
        @Bindable var nav = nav
        return VStack(alignment: .leading, spacing: 12) {
            updateBanner
            tamperedBanner
            Picker("", selection: $nav.tab) {
                Text(l.home).tag(PopoverTab.home)
                Text(l.box).tag(PopoverTab.box)
                Text(l.collection).tag(PopoverTab.collection)
                Text(l.bag).tag(PopoverTab.bag)
                Text(l.shop).tag(PopoverTab.shop)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            // 탭을 옮기면 상세를 닫는다 — 도감에 갔다 오면 박스는 목록부터 보여야 한다.
            .onChange(of: nav.tab) { _, tab in
                boxSelection = nil
                // 탭 전환은 사용자 동작이라 `.onChange` 로 충분하다 — 상세 진입과 달리
                // 이 자리에서 죽는 경로가 없다.
                Breadcrumbs.record("tab: \(tab)")
            }

            if nav.tab == .box {
                BoxTabView(store: player, lines: evoLines, onNeedLine: { baseID in loadLine(baseID) },
                           selection: $boxSelection, fillFrame: store.fillBoxSlots)
            } else if nav.tab == .collection {
                NationalDexView(store: player, provider: provider)
            } else if nav.tab == .bag {
                BagTabView(store: player)
            } else if nav.tab == .shop {
                ShopTabView(store: player, provider: provider, lines: evoLines,
                           onNeedLine: { baseID in loadLine(baseID) })
            } else {
                // 위장이 풀리는 순간을 보고 있는 자리에서 보여준다. 파트너 카드만 감싼다 —
                // 홈 탭 전체를 감싸면 헤더·한도 섹션까지 매초 다시 그려 에너지 예산을 깬다
                // (부화 슬롯이 같은 이유로 같은 모양을 쓴다).
                TimelineView(TogglingSecondTick(isOn: Self.needsDisguiseTick(player.state))) { context in
                    partnerCard
                        .onChange(of: context.date) { _, date in
                            player.revealDisguisesAndNotify(at: date)
                        }
                }
                // 직전 세션이 크래시로 끝났으면 제보를 권한다 — **파트너 카드 바로 아래,
                // 다른 알림들보다 위.** 사용자가 박스를 다시 뒤져 같은 개체를 또 눌러 죽기
                // 전에 먼저 보여야 한다.
                CrashReportCard(store: player, version: AppEnv.appVersion ?? "—")
                // 파트너가 물어 온 것 — 파트너 바로 아래에 둔다(그 개체가 한 일이다).
                DiscoveryCard(store: player) { speciesID in
                    // evoLines 는 **베이스 종**으로 키가 잡혀 있다 — 진화한 개체는
                    // 그 키로 못 찾으므로 라인들을 훑어 이름을 가진 쪽을 쓴다.
                    Self.speciesName(speciesID, in: evoLines, player.language)
                }
                // 알 발견도 파트너가 한 일이라 발견 카드 바로 아래, 부화 슬롯 바로 위에 둔다 —
                // 눌렀을 때 알이 그 아래 줄에 떨어지는 걸 그 자리에서 볼 수 있다. 라인은
                // 위 partnerCard 의 `.task(id: partner.baseID)` 가 이미 같은 키로 요청해 두므로
                // 여기서 새로 fetch 하지 않는다.
                FoundEggAnnouncementCard(store: player, partner: player.state.partner,
                                         line: player.state.partner.flatMap { evoLines[$0.baseID] })
                Divider()
                // 부화 슬롯만 1초 틱을 받는다 — 홈 탭 전체를 `TimelineView` 로 감싸면 파트너
                // 카드·헤더·한도 섹션까지 매초 다시 그려 팝오버 에너지 예산을 깬다.
                //
                // **가지를 나누지 않는다.** 예전엔 `if` 로 감싼 쪽과 안 감싼 쪽을 따로 뒀는데,
                // 마지막 알을 확인해 알이 0개가 되는 순간 가지가 바뀌면서 `EggSlotsView` 가 새로
                // 만들어져 방금 심은 `hatched` 가 날아갔다 — 부화 연출이 안 떴다. 일정만 끈다
                // (알이 없으면 틱도 없다 — `TogglingSecondTick`).
                TimelineView(TogglingSecondTick(isOn: Self.needsCountdownTick(player.state))) { context in
                    EggSlotsView(store: player, now: context.date, lines: evoLines,
                                 onNeedLine: { baseID in loadLine(baseID) },
                                 provider: provider)
                }
                Divider()
                header
                Divider()
                providerStatusBanner   // 인시던트 있을 때만 — 한도 가용 여부와 무관(API 다운=한도 nil 케이스에도)
                if selectedProviderHasLimits {
                    limitsSection
                    Divider()
                }
            }
            footer
        }
        .padding(PopoverMetrics.padding)
    }

    // MARK: 홈 — 파트너 카드

    private func partnerStat(_ title: String, _ value: String) -> some View {
        HStack(spacing: 3) {
            Text(title).font(.system(size: 9)).foregroundStyle(.tertiary)
            Text(value).font(.system(size: 10, weight: .medium)).monospacedDigit()
        }
    }

    /// 파트너 이름. 진화 라인을 아직 못 받았으면 번호로 떨어진다 — 라인은 아래 `.task` 가
    /// 진화 배지를 위해 이미 받아 두는데, 정작 이름에는 안 쓰고 번호만 보여주고 있었다.
    private func partnerName(_ partner: Individual) -> String {
        let species = evoLines[partner.displayLineID]?
            .localizedName(partner.displaySpeciesID, player.language) ?? "#\(partner.displaySpeciesID)"
        return partner.displayName(speciesName: species, player.language)
    }

    /// 파트너의 알 게이지. **알림 카드(`FoundEggAnnouncementCard`)와 같은 조건·같은 동작**이다 —
    /// 다른 건 하나뿐, 이쪽은 아직 덜 찼을 때도 얼마나 왔는지 보여 준다. 위장 중이거나 라인이
    /// 아직 안 왔으면 아무것도 안 낸다(모르면 안 보여 준다 — `showsEvolutionBadge` 와 같은 원칙).
    @ViewBuilder
    private func eggGauge(for partner: Individual) -> some View {
        if partner.disguisedAs == nil, let line = evoLines[partner.baseID] {
            let threshold = ExpBalance.eggThreshold(grade: partner.grade)
            HomeEggGauge(grade: partner.grade,
                         progress: IndividualDetailView.eggProgress(partner),
                         shaking: HomeEggGauge.shouldShake(
                             full: partner.eggProgress >= threshold,
                             hasFreeSlot: player.freeSlots > 0)) {
                player.takeFoundEgg(individualID: partner.id, line: line)
            }
        }
    }

    /// 홈 상단 — 지금 데리고 다니는 개체의 초상화 + 경험치 진행도. 파트너 상세(진화 실행 등)는 박스에서.
    @ViewBuilder
    private var partnerCard: some View {
        if let partner = player.state.partner {
            HStack(alignment: .top, spacing: 10) {
                SpriteView(speciesID: partner.displaySpeciesID, form: partner.spriteForm, size: 64, bob: true, animated: true,
                          shiny: partner.showsShiny, antialias: store.antialiasSprites)
                    .frame(width: 64, height: 64)
                    .background(Color.secondary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    // 쓰다듬은 표시 — **아주 작게 한 번**(사용자 결정). 크게 내면 숨은 조작이
                    // 아니게 되고, 아무것도 안 내면 발견해도 되는지 알 수 없다.
                    .overlay(alignment: .top) {
                        if showHeart {
                            Text("♥")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.pink)
                                .offset(y: heartRise)
                                .opacity(heartOpacity)
                        }
                    }
                    // **쓰다듬기(숨은 조작).** 이 초상은 지금까지 아무 제스처도 없었으므로
                    // 길게 누르기가 통째로 비어 있다 — 기존 조작을 하나도 안 뺏는다.
                    // 플로팅 펫이 아니라 여기 둔 이유: 펫은 옵트인이라 안 켠 사람은 발견할
                    // 길이 자체가 없다(사용자 지적).
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in if pettingSince == nil { pettingSince = Date() } }
                            .onEnded { _ in
                                defer { pettingSince = nil }
                                guard let start = pettingSince else { return }
                                guard player.petPartner(heldFor: Date().timeIntervalSince(start)) > 0
                                else { return }
                                heartRise = 0
                                heartOpacity = 1
                                showHeart = true
                                withAnimation(.easeOut(duration: 0.9)) {
                                    heartRise = -30
                                    heartOpacity = 0
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.95) {
                                    showHeart = false
                                }
                            }
                    )
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(partnerName(partner)).font(.callout.weight(.semibold))
                        if partner.showsShiny { Text("✨").font(.system(size: 11)) }
                        Text(l.levelLabel(partner.level))
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.18), in: Capsule())
                        Text(partner.grade.label(player.language))
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.18), in: Capsule())
                        if let ribbon = partner.ribbon(at: player.currentDate()) {
                            HStack(spacing: 2) {
                                RibbonIcon(ribbon: ribbon, size: 12)
                                Text(ribbon.label(player.language))
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.orange.opacity(0.20), in: Capsule())
                        }
                        if showsEvolutionBadge(for: partner) {
                            Text(l.evolutionReadyBadge)
                                .font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Color.orange, in: Capsule())
                        }
                        // 알 게이지는 이 줄 오른쪽 끝 — 이름·레벨과 같은 층위다. 바로 아래
                        // 경험치 바와 형태부터 갈라야 해서(가로 막대 vs 세로로 차는 알) 여기 둔다.
                        Spacer(minLength: 4)
                        eggGauge(for: partner)
                    }
                    Text(partner.nature.name(player.language))
                        .font(.caption2).foregroundStyle(.secondary)
                    // 레벨 진행도 — 상세 화면과 같은 계산(`IndividualDetailView.levelProgress`)을
                    // 써야 두 화면이 같은 개체를 다른 퍼센트로 그리지 않는다. 주황은 사탕
                    // (`CandyMeter`)에 넘겼다: 둘 다 주황 5pt 이던 시절엔 어느 쪽이 무엇인지
                    // 구분이 안 됐다.
                    ProgressView(value: IndividualDetailView.levelProgress(partner))
                        .progressViewStyle(.linear).frame(height: 5)
                    // 리본이 있으면 **지금 무엇을 채우고 있는지**를 경험치 바로 아래에 둔다.
                    // 둘 다 이 파트너가 채우는 것이라 같은 층위이고, 예전에는 홈 어디에도
                    // 리본이 안 보여 사탕이 언제 나오는지 알 길이 없었다.
                    if let ribbon = partner.ribbon(at: player.currentDate()) {
                        CandyMeter(
                            progress: IndividualDetailView.candyProgress(partner, ribbon),
                            remaining: TokenFormatter.compact(
                                max(0, ribbon.tokensPerCandy - partner.candyProgress)),
                            label: l.ribbonNextCandy)
                    }
                    // 이 아이와 얼마나, 얼마만큼 — 경험치 게이지가 못 보여주는 누적을 여기서 보여준다.
                    HStack(spacing: 10) {
                        partnerStat(l.detailPartnerTime,
                                    Individual.togetherText(
                                        seconds: partner.partnerDuration(at: player.currentDate()), l))
                        partnerStat(l.detailPartnerTokens,
                                    TokenFormatter.compact(partner.partnerTokens))
                    }
                }
                Spacer()
            }
            .task(id: partner.baseID) {
                // 홈에서도 배지를 정확히 판단하려면 라인이 필요하다 — 박스 탭을 먼저 안 열어도 로드되게.
                if evoLines[partner.baseID] == nil { loadLine(partner.baseID) }
            }
        }
    }

    /// 홈 진화 배지 표시 여부 — 라인이 아직 없으면(로딩 중) 배지를 숨긴다. 라인 미로드 상태에서
    /// 배지부터 보여주면, 나중에 최종형으로 판명될 때 "눌러도 갈 곳 없는" 배지를 보여준 셈이
    /// 된다 — 판단 못 하면 아무것도 보여주지 않는다. 판정 자체는 `PlayerStore.isReadyToEvolve`
    /// **한 곳**에만 있다(박스 칸 배지와 공유) — 화면마다 따로 적으면 갈린다.
    private func showsEvolutionBadge(for partner: Individual) -> Bool {
        guard let line = evoLines[partner.baseID] else { return false }
        return player.isReadyToEvolve(partner, line: line)
    }

    // MARK: 박스 — 진화 라인 로드

    /// 박스 검색과 진화 후보에 필요한 라인. 박스 전체와 상세 화면의 요청을 공유한다.
    /// 여러 화면이 같은 라인을 요청할 수 있으므로, `loadingLines` 에
    /// 먼저 등록해 나머지 호출을 조기 반환시킨다 — 실패해도 `defer` 로 등록을 지워 재시도는 막지 않는다.
    private func loadLine(_ baseID: Int) {
        guard Self.shouldStartLoadingLine(baseID, loadedIDs: Set(evoLines.keys), loadingIDs: loadingLines) else { return }
        loadingLines.insert(baseID)
        Task {
            defer { loadingLines.remove(baseID) }
            if let line = try? await provider.line(baseSpeciesID: baseID) {
                evoLines[baseID] = line
                // 라인이 아는 종은 여기서 성장 곡선을 바로잡는다 — 마이그레이션된 개체·스타터가
                // 진화 없이도(이미 최종형이면 영영 진화가 안 온다) 맞는 곡선을 받게 하는 유일한 자리다.
                player.backfillGrowthRates(from: line)
                player.backfillGenders(from: line)
            }
        }
    }

    // MARK: 헤더 — 오늘 합계 + provider/토큰타입 분해

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(l.todayTokens)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline) {
                Text(TokenFormatter.compact(store.todayTotalTokens))
                    .font(.system(size: 28, weight: .bold))
                    .monospacedDigit()
                Text(TokenFormatter.grouped(store.todayTotalTokens))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                if store.showsCost {
                    Text(TokenFormatter.cost(todayCost))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            // 주간/월간 누적 (전 서비스 합산 — 오늘 합계와 함께 통합 통계)
            if store.weekTotalTokens > 0 || store.monthTotalTokens > 0 {
                HStack(spacing: 14) {
                    periodLabel(l.thisWeek, tokens: store.weekTotalTokens, cost: store.showsCost ? store.weekCostTotal : nil)
                    periodLabel(l.thisMonth, tokens: store.monthTotalTokens, cost: store.showsCost ? store.monthCostTotal : nil)
                    Spacer()
                }
                .padding(.top, 2)
            }

            MonthDailyTrend(series: store.monthDailyTotals,
                            showsCost: store.showsCost,
                            today: LocalUsageReader.todayKey(),
                            l: l)

            // 연결된 서비스가 2개 이상이면 작은 탭으로 서비스별 상세를 넘나든다
            // (합계는 위에 유지 — 상세·한도만 탭 스코프).
            if store.snapshots.count > 1 {
                providerTabBar
                    .padding(.top, 6)
            }
            if let snap = selectedSnapshot, let today = snap.today {
                providerRow(snapshot: snap, today: today)
            }
        }
    }

    /// 현재 선택된 프로바이더 스냅샷 — 선택이 없거나 연결 해제됐으면 첫 번째로 폴백.
    private var selectedSnapshot: ProviderSnapshot? {
        store.snapshot(preferring: nav.providerID)
    }

    private var providerTabBar: some View {
        ProviderTabBar(
            snapshots: store.snapshots,
            selectedID: selectedSnapshot?.providerID,
            onSelect: { nav.providerID = $0 })
    }

    private func periodLabel(_ name: String, tokens: Int, cost: Double?) -> some View {
        HStack(spacing: 4) {
            Text(name)
                .font(.caption)
                .foregroundStyle(.tertiary)
            Text(TokenFormatter.compact(tokens))
                .font(.caption.weight(.semibold))
                .monospacedDigit()
            if let cost {
                Text(TokenFormatter.cost(cost))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var todayCost: Double {
        store.costingSnapshots.reduce(0) { $0 + ($1.today?.totalCost ?? 0) }
    }

    private func providerRow(snapshot: ProviderSnapshot, today: DailyUsage) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(snapshot.displayName)
                    .font(.callout.weight(.semibold))
                Spacer()
                Text(TokenFormatter.compact(today.totalTokens))
                    .font(.callout)
                    .monospacedDigit()
                if snapshot.reportsCost {
                    Text(TokenFormatter.cost(today.totalCost))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 10) {
                tokenTypeLabel("in", today.inputTokens)
                tokenTypeLabel("out", today.outputTokens)
                tokenTypeLabel("cache w", today.cacheCreationTokens)
                tokenTypeLabel("cache r", today.cacheReadTokens)
            }
        }
        .padding(.top, 2)
    }

    private func tokenTypeLabel(_ name: String, _ value: Int) -> some View {
        HStack(spacing: 3) {
            Text(name)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(TokenFormatter.compact(value))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    // MARK: 한도 섹션 — 공식 5h/주간 % + 리셋 카운트다운

    /// 선택된 프로바이더에 표시할 공식 한도가 있는가 (Gemini 는 공식 한도 API 없음 → 섹션 생략).
    private var selectedProviderHasLimits: Bool {
        switch selectedSnapshot?.providerID {
        // Keychain 이 꺼져있지 않으면 한도가 아직 없어도 섹션을 노출한다 — 그래야 최초 실행에
        // claudeLimitsRefreshRow("탭해서 로드")가 보여, 설정까지 안 들어가도 원탭으로 켤 수 있다.
        // (자동 Keychain 읽기는 팝업 방지로 여전히 안 함 — 발견성만 살린다.)
        case "claude_code": return !store.disableKeychainAccess || store.limits != nil || store.limitsAuthExpired
        case "codex": return store.codexLimits?.hasVisibleLimit == true
        default: return false
        }
    }

    /// 선택 프로바이더의 상태 페이지 인시던트(있을 때만) — Claude/OpenAI API 장애를 앱 고장으로
    /// 오인하지 않게. 표시 전용(알림 아님). 인시던트 없거나 상태조회 꺼짐이면 아무것도 안 그림.
    /// 범위(v1): 선택된 provider 탭 한정. 오늘 안 쓴 provider 는 탭/스냅샷이 없어 배너도 안 뜬다 —
    /// 오인이 실제로 생기는 케이스(오늘 써서 이상 수치를 보는데 한도는 nil)는 로컬 사용 스냅샷이 있어
    /// 탭이 존재하므로 커버된다. 전 provider 전역 인시던트 행은 추후.
    @ViewBuilder
    private var providerStatusBanner: some View {
        if let id = selectedSnapshot?.providerID,
           let status = store.providerStatus(for: id), status.indicator.hasIssue {
            HStack(spacing: 6) {
                Circle().fill(statusColor(status.indicator)).frame(width: 7, height: 7)
                Text(l.providerStatusLabel(status.indicator))
                    .font(.caption).fontWeight(.medium)
                if !status.description.isEmpty {
                    Text(status.description)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
            }
        }
    }

    private func statusColor(_ indicator: ProviderStatusIndicator) -> Color {
        switch indicator {
        case .operational:         return .green
        case .minor, .maintenance: return .yellow
        case .major:               return .orange
        case .critical:            return .red
        case .unknown:             return .gray
        }
    }

    @ViewBuilder
    private var limitsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(l.limitsOfficial)
                .font(.caption)
                .foregroundStyle(.secondary)
            if selectedSnapshot?.providerID == "claude_code", store.limitsAuthExpired {
                claudeAuthExpiredNotice
            } else if selectedSnapshot?.providerID == "claude_code",
                      !store.disableKeychainAccess,
                      store.limits == nil || store.claudeLimitsStale {
                // 자동 폴링은 Keychain 을 안 읽으므로(팝업 방지), 최초/만료 후 공식 한도는 이 원탭으로
                // 사용자가 직접 갱신한다. 프롬프트가 뜨더라도 사용자 행동에 의한 것이라 예상 가능하다.
                claudeLimitsRefreshRow
            }
            if selectedSnapshot?.providerID == "claude_code", let limits = store.limits {
                // 플랜(계정 속성) — Codex codexMetaRow 와 동일 스타일. 구독 정보 있을 때만 노출.
                if let plan = limits.planDisplay {
                    Text(l.plan(plan))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                // 세션 만료 시 표시값은 만료 전 기준 → 흐리게 처리해 "현재 값 아님"을 시각적으로 전달
                VStack(alignment: .leading, spacing: 8) {
                    limitRow(name: l.fiveHourSession, window: limits.fiveHour)
                    forecastRow
                    limitRow(name: l.weekly, window: limits.sevenDay)
                    limitRow(name: l.weeklyOpus, window: limits.sevenDayOpus)
                    limitRow(name: l.weeklySonnet, window: limits.sevenDaySonnet)
                    // 신형 limits[] — 모델별 주간(weekly_scoped) 등 레거시 필드 밖 윈도우
                    ForEach(Array(limits.scopedLimitEntries.enumerated()), id: \.offset) { _, entry in
                        limitRow(
                            name: l.claudeLimitEntry(kind: entry.kind, model: entry.scope?.model?.displayName),
                            window: LimitWindow(utilization: entry.percent, resetsAt: entry.resetsAt))
                    }
                    // 전 프로바이더가 블록을 갖게 됨 — "Claude 현재 5h 블록" 행은 명시 조회
                    if let block = store.snapshots.first(where: { $0.providerID == "claude_code" })?.activeBlock,
                       let end = block.endDate {
                        HStack {
                            Text(l.claudeCurrentBlock)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(TokenFormatter.compact(block.totalTokens))
                                .font(.caption)
                                .monospacedDigit()
                            Spacer()
                            (Text("\(l.reset) ") + Text(end, style: .relative) + resetClockSuffix(end))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .opacity(store.limitsAuthExpired ? 0.5 : 1)
            }
            if selectedSnapshot?.providerID == "codex",
               let codexStatus = store.codexLimits, codexStatus.hasVisibleLimit {
                let buckets = codexStatus.visibleSnapshots
                codexMetaRow(codexStatus)
                // id 는 offset — limitId 가 nil 인 bucket 이 2개 이상이면 \.limitId 는 충돌(행 누락)한다.
                // snapshots 순서는 결정적(sorted)이라 offset 안정. (scopedLimitEntries 와 동일 방식)
                ForEach(Array(buckets.enumerated()), id: \.offset) { _, bucket in
                    // bucket 이 여럿일 때만 구분 라벨 (단일 bucket 사용자는 기존 UI 그대로)
                    if buckets.count > 1 {
                        Text(bucket.bucketDisplayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                    }
                    codexLimitRow(name: l.codexWindow(bucket.primary?.windowDurationMins), window: bucket.primary)
                    codexLimitRow(name: l.codexWindow(bucket.secondary?.windowDurationMins), window: bucket.secondary)
                    codexSpendLimitRow(bucket.individualLimit)
                }
            }
        }
    }


    /// 한도 % 표시 문자열 — remaining 모드면 남은 %에 자기설명 접미사("남음/left/残り").
    /// 게이지 채움도 같은 표시 모드를 따르며, 경고색은 실제 사용률로 판단한다.
    private func limitPercentText(_ utilization: Double) -> String {
        let text = TokenFormatter.percent(store.limitDisplayPercent(utilization))
        return store.limitDisplayMode == .remaining ? l.percentRemaining(text) : text
    }

    /// 리셋이 이 창 안(≤ 6h)이거나 오늘이면 벽시계 접미사를 "HH:mm" 만으로 짧게 낸다.
    /// 그 밖(주간 한도 등 며칠 뒤)이면 요일·일자를 붙여 "HH:mm" 만으로 생기는 오해를 막는다.
    /// 어느 쪽이든 접미사는 항상 붙는다 — 프로바이더 리터럴 분기 없이 리셋 근접도만 본다
    /// (확장 규약: 플랫폼 종속 분기 금지).
    private static let resetClockWindow: TimeInterval = 6 * 3600

    /// 카운트다운 뒤에 붙는 절대 리셋 시각 " (…)". 오늘 안이거나 ≤ 6h 면 시:분만,
    /// 며칠 뒤(주간 한도 등)면 요일·일자까지 — "in 2 days, 9 hr" 만으론 언제 풀리는지 감이 안 와서다.
    /// 요일명은 팝오버 로케일(companion.language)로 현지화하고, 시각은 항상 24시간 표기.
    private func resetClockSuffix(_ reset: Date) -> Text {
        let f = DateFormatter()
        f.locale = player.language.displayLocale
        f.setLocalizedDateFormatFromTemplate(Self.resetClockFormatTemplate(reset: reset, now: Date()))
        return Text(" (\(f.string(from: reset)))")
    }

    /// 포맷 템플릿 선택(순수) — 오늘 안/≤6h 면 시:분, 그 밖이면 요일·일자 포함.
    nonisolated static func resetClockFormatTemplate(reset: Date, now: Date) -> String {
        let nearby = Calendar.current.isDate(reset, inSameDayAs: now)
            || reset.timeIntervalSince(now) <= resetClockWindow
        return nearby ? "HHmm" : "EEEEdHHmm"
    }
    private func resetLabel(_ reset: Date) -> Text {
        Text("· \(reset, style: .relative)") + resetClockSuffix(reset)
    }

    @ViewBuilder
    private func limitRow(name: String, window: LimitWindow?) -> some View {
        if let window, let utilization = window.utilization {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(name)
                        .font(.callout)
                    Spacer()
                    Text(limitPercentText(utilization))
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(limitColor(utilization))
                    if let reset = window.resetDate {
                        resetLabel(reset)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                LimitProgressBar(usedPercent: utilization, tint: limitColor(utilization))
            }
        }
    }

    @ViewBuilder
    private func codexMetaRow(_ status: CodexRateLimitStatus) -> some View {
        // plan 은 계정 속성 — bucket 필터와 무관하게 top-level 에서 읽는다 (로그와 동일 소스)
        let planType = status.rateLimits.planType ?? status.visibleSnapshots.first?.planType
        let reached = status.visibleSnapshots.contains { $0.rateLimitReachedType != nil }
        if planType != nil || reached || store.codexLimitsStale {
            HStack(spacing: 8) {
                if let plan = planType {
                    Text(l.plan(plan))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                if reached {
                    Text(l.limitReached)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                // 갱신 실패가 15분+ 이어지면 이전 스냅샷임을 노출 (codex TUI stale 임계와 동일)
                if store.codexLimitsStale {
                    staleBadge(updatedAt: store.codexLimitsUpdatedAt)
                }
            }
        }
    }

    /// Claude 세션 만료(401) 안내 — 자동 폴링은 만료 토큰을 스스로 못 고치므로,
    /// "왜 어제 값에 멈췄는지 + 원탭 재시도 + Claude Code 실행 시 자동 갱신" 을 눈에 띄게 노출.
    @ViewBuilder
    private var claudeAuthExpiredNotice: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(l.claudeAuthExpiredTitle)
                    .font(.caption).fontWeight(.semibold)
                Spacer()
                Button {
                    Task { await store.refreshLimitTokenFromKeychain() }
                } label: {
                    if store.isRefreshingLimitToken {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(l.retry)
                    }
                }
                .controlSize(.small)
                .disabled(store.isRefreshingLimitToken)
            }
            Text(l.claudeAuthExpiredHint)
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(8)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    /// Claude 공식 한도 — 최초 로드/만료(stale) 시 사용자가 원탭으로 Keychain 을 읽어 갱신.
    /// 자동 폴링이 Keychain 을 안 읽는 대신 여기서 명시적 사용자 동작으로만 재취득한다.
    @ViewBuilder
    private var claudeLimitsRefreshRow: some View {
        HStack(spacing: 6) {
            if store.limits == nil {
                Text(l.limitsTapToLoad)
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                (Text(l.staleLimits) + Text(" · ") + Text(store.limitsUpdatedAt ?? Date(), style: .relative))
                    .font(.caption).foregroundStyle(.orange)
            }
            Spacer()
            Button {
                Task { await store.refreshLimitTokenFromKeychain() }
            } label: {
                if store.isRefreshingLimitToken {
                    ProgressView().controlSize(.small)
                } else {
                    Text(l.refresh)
                }
            }
            .controlSize(.small)
            .disabled(store.isRefreshingLimitToken)
        }
    }

    /// 한도 스냅샷 갱신 지연 배지 — Claude/Codex 공용 (마지막 성공 시각 상대 표시).
    @ViewBuilder
    private func staleBadge(updatedAt: Date?) -> some View {
        if let updatedAt {
            (Text(l.staleLimits) + Text(" · ") + Text(updatedAt, style: .relative))
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private func codexLimitRow(name: String, window: CodexRateLimitWindow?) -> some View {
        if let window {
            let utilization = Double(window.usedPercent)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(name)
                        .font(.callout)
                    Spacer()
                    Text(limitPercentText(utilization))
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(limitColor(utilization))
                    if let reset = window.resetDate {
                        resetLabel(reset)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                LimitProgressBar(usedPercent: utilization, tint: limitColor(utilization))
            }
        }
    }

    @ViewBuilder
    private func codexSpendLimitRow(_ limit: CodexSpendControlLimit?) -> some View {
        if let limit {
            let utilization = Double(limit.usedPercent)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(l.personalSpendLimit)
                        .font(.callout)
                    Spacer()
                    Text("\(limit.used) / \(limit.limit)")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Text(limitPercentText(utilization))
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(limitColor(utilization))
                    resetLabel(limit.resetDate)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                LimitProgressBar(usedPercent: utilization, tint: limitColor(utilization))
            }
        }
    }

    /// 한도 소진 예측 — 현재 burn rate 로 5h 한도 100% 도달 시각 외삽
    @ViewBuilder
    private var forecastRow: some View {
        if let forecast = store.fiveHourForecast {
            HStack(spacing: 4) {
                Image(systemName: forecast.beforeReset
                    ? "exclamationmark.triangle.fill" : "checkmark.circle")
                    .font(.caption2)
                Text(forecast.beforeReset
                    ? l.forecastReach(Self.timeFormatter.string(from: forecast.depletionDate))
                    : l.forecastNoReach)
                    .font(.caption)
            }
            .foregroundStyle(forecast.beforeReset ? AnyShapeStyle(.orange) : AnyShapeStyle(.tertiary))
            .padding(.leading, 2)
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private func limitColor(_ utilization: Double) -> Color {
        if utilization >= store.critThreshold { return .red }
        if utilization >= store.warnThreshold { return .orange }
        return .green
    }

    // MARK: 푸터

    /// 조작된 세이브 표시 — 뒤집힌 스프라이트만 보고 "버그인가?" 하지 않도록 이유를 적어 둔다.
    @ViewBuilder
    private var tamperedBanner: some View {
        if player.state.tampered {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10)).foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 1) {
                    Text(l.tamperedBadge).font(.system(size: 10, weight: .semibold))
                    Text(l.tamperedExplanation).font(.system(size: 9)).foregroundStyle(.secondary)
                }
            }
            .padding(6)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            // 갱신·"Updated" 시각·에러 삼각형은 사용량 신선도 UI — 사용량을 표시하지 않는 탭(도감/가방/상점)에선
            // "뭘 갱신하라는 건지" 혼란만 줘서 홈 탭에서만 노출한다. 설정/종료는 전역이라 아래에 그대로 둔다.
            if nav.tab == .home {
                // 스피너 스왑을 두지 않는다 — 로컬 파싱이 보이는 오늘 숫자를 즉시 갱신하는데
                // enrichment/한도(네트워크)까지 기다리는 스피너가 데이터보다 오래 돌아 불필요해 보였다.
                // 중복 클릭은 refresh() 의 재진입 guard 가 무시하고, 피드백은 아래 "Updated" 시각이 준다.
                Button {
                    Task { await store.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help(l.refreshNow)
                if let updated = store.lastUpdated {
                    (Text("\(l.updated) ") + Text(updated, style: .relative))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                if store.lastErrorDescription != nil {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .help(store.lastErrorDescription ?? "")
                }
            }
            Spacer()
            Button {
                nav.showSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help(l.settings)
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .help(l.quit)
        }
    }
}

/// 이번 달 일별 추이 — 주/월 스칼라 두 개로는 답할 수 없는 "지난 며칠 어땠나"를 채운다.
///
/// 데이터는 이미 메모리에 있다(`ProviderEnrichment.monthDaily` — enrichment 스캔이 월 전체를
/// 읽고 있었고, 지금까지 합계만 남기고 버렸다). 새 창을 만들지 않고 기존 헤더 결을 따라 캡션 한 줄
/// + 막대 한 줄로 접는다.
///
/// 표시 게이트는 **의미값**이다(`peak > 0`). `series.isEmpty` 나 `!= nil` 로 게이트하면 안 된다 —
/// 생산자가 사용 없는 날도 0 으로 채우므로 이번 달을 한 번도 안 쓴 사용자에게도 배열은 non-empty 라
/// #56 계열(옵셔널 tautology)의 "안 썼는데 왜 뜨지"가 재현된다.
@MainActor
struct MonthDailyTrend: View {
    let series: [DailyUsage]
    let showsCost: Bool
    /// 오늘의 `localDay` 키 — 강조할 막대를 뷰가 시계를 다시 읽어 고르지 않게 주입한다.
    let today: String
    let l: L

    /// 마우스가 올라간 막대. 캡션의 리드아웃이 이걸 따라가고, 벗어나면 오늘로 돌아온다.
    /// 툴팁(`.help`)과 달리 **지연이 없고, 안 올려도 오늘 값이 항상 보인다** — 날짜를 알려면
    /// 반드시 호버해야 했던 게 첫 버전의 불만이었다.
    @State private var hovered: String?

    var body: some View {
        let peak = series.map(\.totalTokens).max() ?? 0
        if peak > 0 {
            VStack(alignment: .leading, spacing: 3) {
                captionRow(peak: peak)
                barRow(peak: peak)
                weekendTickRow
                axisRow
            }
            .padding(.top, 4)
        }
    }

    /// 캡션 + 리드아웃(호버 중인 날, 없으면 오늘) + 최댓값.
    /// 최댓값을 남기는 이유: 막대 높이가 상대값이라 어딘가 한 곳은 절대 스케일을 적어야 한다.
    private func captionRow(peak: Int) -> some View {
        HStack(spacing: 5) {
            Text(l.dailyTrend)
                .font(.caption)
                .foregroundStyle(.tertiary)
            Text(readout)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Spacer()
            Text(l.peakDay)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(TokenFormatter.compact(peak))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func barRow(peak: Int) -> some View {
        HStack(alignment: .bottom, spacing: DailyTrendMetrics.spacing) {
            ForEach(series, id: \.date) { day in
                let isToday = day.date == today
                // 사용 0 인 날은 바닥 눈금만 남으므로, 아주 조금 쓴 날과 높이로는 구분되지
                // 않는다 — 색을 한 단계 흐리게 해 "안 쓴 날"과 "조금 쓴 날"을 갈라준다.
                let isEmptyDay = day.totalTokens == 0
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(isToday ? Color.accentColor
                                  : Color.secondary.opacity(isEmptyDay ? 0.18 : 0.45))
                    .frame(height: DailyTrendMetrics.barHeight(tokens: day.totalTokens, peak: peak))
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())   // 낮은 막대도 칼럼 전체가 호버 대상이 되게
                    .onHover { inside in hovered = inside ? day.date : nil }
            }
        }
        .frame(height: DailyTrendMetrics.track, alignment: .bottom)
    }

    /// 주말 칼럼에 짧은 밑줄. **전체 높이 음영으로 하면 안 된다** — 다크 배경에서 그 음영이
    /// 막대로 읽혀 주말이 큰 사용량인 것처럼 보인다(후보 B 를 렌더해서 확인하고 버렸다).
    private var weekendTickRow: some View {
        HStack(spacing: DailyTrendMetrics.spacing) {
            ForEach(series, id: \.date) { day in
                Rectangle()
                    .fill(DailyTrendMetrics.isWeekend(day.date)
                          ? Color.secondary.opacity(0.5) : Color.clear)
                    .frame(height: DailyTrendMetrics.tickHeight)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// 날짜 축. 막대 폭이 한 달 기준 약 9pt 라 두 자리 숫자가 다 안 들어가므로 **전부 붙이면
    /// 서로 겹친다** — 1일·7일 간격·오늘에만 붙이고 나머지 칼럼은 빈 자리로 폭을 맞춘다
    /// (빈 자리를 빼면 라벨이 막대와 어긋난다).
    private var axisRow: some View {
        HStack(spacing: DailyTrendMetrics.spacing) {
            ForEach(series, id: \.date) { day in
                Group {
                    if let label = DailyTrendMetrics.axisLabel(for: day.date, today: today) {
                        Text(label)
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(day.date == today ? Color.accentColor : Color.secondary)
                            .fixedSize(horizontal: true, vertical: false)
                    } else {
                        Color.clear.frame(height: 1)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    /// 호버 중인 날(없으면 오늘)의 "8/24 (월) 5.2M". 시리즈에 없는 날짜면 빈 문자열 —
    /// 프로덕션에선 시리즈가 항상 오늘로 끝나므로 조회 실패는 일어나지 않는다(배열 조회가
    /// 옵셔널이라 생기는 분기일 뿐, 테스트할 분기가 아니다).
    private var readout: String {
        let target = hovered ?? today
        guard let day = series.first(where: { $0.date == target }) else { return "" }
        let stamp = DailyTrendMetrics.dayStamp(day.date, language: l.lang)
        let tokens = TokenFormatter.compact(day.totalTokens)
        guard showsCost, day.totalCost > 0 else { return "\(stamp) \(tokens)" }
        return "\(stamp) \(tokens) \(TokenFormatter.cost(day.totalCost))"
    }
}

/// 추이 막대의 기하 — 뷰 밖의 순수 함수로 둔다. SwiftUI 안에 두면 헤드리스로 검증할 수 없고,
/// 이 계산은 0 과 최댓값 경계에서 조용히 틀리기 쉽다(0 을 0pt 로 그리면 "그날이 없는" 것처럼 보인다).
enum DailyTrendMetrics {
    /// 막대 트랙 높이. 헤더가 이미 촘촘하므로 스파크라인 수준으로 낮게 잡는다.
    static let track: CGFloat = 26
    static let spacing: CGFloat = 1.5
    /// 사용 없는 날에 남기는 바닥 눈금. 0pt 로 그리면 그 날짜 칸이 사라진 것처럼 보이고, 축이
    /// 밀리지 않았다는 사실(=0 을 명시적으로 채웠다)이 화면에서 안 읽힌다.
    static let baseline: CGFloat = 1.5
    /// 주말 표시 밑줄 두께.
    static let tickHeight: CGFloat = 1.5

    /// `tokens` 를 `peak` 대비 비율로 트랙 안에 눕힌다.
    /// - `peak <= 0`: 스케일이 없다 → 전부 바닥 눈금 (호출부가 이미 게이트하지만 0 나눗셈은 막는다).
    /// - `tokens <= 0`: 바닥 눈금.
    /// - 그 외: 최소 `baseline` 을 보장해 아주 작은 날도 사라지지 않는다.
    static func barHeight(tokens: Int, peak: Int) -> CGFloat {
        guard peak > 0, tokens > 0 else { return baseline }
        let ratio = min(1, Double(tokens) / Double(peak))
        return max(baseline, CGFloat(ratio) * track)
    }

    /// 축에 숫자를 붙일 날인가 — 1일, 7일 간격, 그리고 오늘.
    ///
    /// 오늘을 항상 붙이는 이유: 오늘 사용량이 적으면 막대가 바닥 눈금 한 줄이라 강조색만으로는
    /// 위치를 못 찾는다(31일 렌더에서 실제로 안 보였다). 축의 숫자가 그때 유일한 단서다.
    ///
    /// **오늘 옆의 정기 라벨은 지운다.** 한 달이 다 찬 축은 칼럼이 약 9pt 인데 두 자리 숫자는
    /// 약 11pt 라, 오늘이 7의 배수 바로 옆이면(22일·29일 등) `21 22` 가 간격 없이 붙어 한 숫자로
    /// 읽힌다(8월 실데이터로 렌더해서 확인했다). 오늘은 절대 지우지 않으므로 라벨이 0개가 되는
    /// 상태는 없고, 인접한 정기 라벨 하나를 잃는 대가는 없다 — 오늘 위치를 알면 그 옆도 안다.
    static func axisLabel(for date: String, today: String, labelInterval: Int = 7,
                          minimumSeparation: Int = 3) -> String?
    {
        // `Int(...)` 옵셔널 해제는 API 강제다 — 시리즈의 날짜는 항상 "yyyy-MM-dd" 라 실패하지
        // 않는다(테스트할 분기가 아니다).
        guard let dayOfMonth = Int(date.suffix(2)) else { return nil }
        if date == today { return "\(dayOfMonth)" }

        let isRegular = dayOfMonth == 1 || (labelInterval > 0 && dayOfMonth % labelInterval == 0)
        guard isRegular else { return nil }
        if let todayOfMonth = Int(today.suffix(2)),
           abs(dayOfMonth - todayOfMonth) < minimumSeparation { return nil }
        return "\(dayOfMonth)"
    }

    /// `calendar` 는 테스트 주입 구멍 — 주말이 어느 요일인지는 로케일이 정한다(금·토인 지역도
    /// 있다). 프로덕션은 사용자 달력을 그대로 따라야 하므로 기본값을 쓴다.
    static func isWeekend(_ date: String, calendar: Calendar = .current) -> Bool {
        guard let parsed = LocalUsageReader.localDayFormatter().date(from: date) else { return false }
        return calendar.isDateInWeekend(parsed)
    }

    /// 월·일 + 요일을 **그 언어가 쓰는 순서로** — ko "8. 24. (월)", en "Mon, 8/24", fr "lun. 24/08".
    ///
    /// 두 가지를 로케일 템플릿(`MdE`)에 맡긴다.
    /// ① **요일 이름**: 6개 언어 × 7요일을 `Localization.swift` 에 손으로 적으면 OS 가 이미 가진 것을
    ///    다시 적는 셈이다.
    /// ② **월·일 순서**: `"\(month)/\(day)"` 로 조립하면 프랑스어·스페인어·포르투갈어에서도 미국식
    ///    순서(8/24)가 강제된다 — 그 언어들은 24/08 이 맞다.
    ///
    /// 로케일은 반드시 `AppLanguage` 에서 온다. `DateFormatter` 를 기본값으로 만들면 시스템 로케일을
    /// 따라, 앱 언어를 바꾼 사용자에게 한 화면 두 언어가 된다(defect-log §표시·UI 의 `.relative` 부류).
    static func dayStamp(_ date: String, language: AppLanguage) -> String {
        guard let parsed = LocalUsageReader.localDayFormatter().date(from: date) else { return "" }
        let formatter = DateFormatter()
        formatter.locale = language.displayLocale
        formatter.setLocalizedDateFormatFromTemplate("MdE")
        return formatter.string(from: parsed)
    }
}

/// 서비스 전환 탭. 프로바이더가 늘면 캡슐 합계 폭이 `PopoverMetrics.contentWidth` 를 넘는다
/// (6개 기준 439pt vs 332pt). 폭 제한만 있고 줄바꿈을 막지 않으면 SwiftUI 가 캡슐 텍스트를 눌러
/// "Curso/r"·"Code/x" 처럼 **단어 중간에서** 접고 탭 바가 2~3줄이 된다.
/// 가로 스크롤 + `lineLimit(1)`/`fixedSize` 로 각 탭이 항상 자연 폭 한 줄을 유지한다.
/// (`Spacer()` 는 가로 ScrollView 안에서 무한 확장하므로 쓰지 않는다.)
struct ProviderTabBar: View {
    let snapshots: [ProviderSnapshot]
    let selectedID: String?
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(snapshots) { snap in
                    let isSelected = snap.providerID == selectedID
                    Button { onSelect(snap.providerID) } label: {
                        Text(snap.displayName)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .font(.caption.weight(isSelected ? .semibold : .regular))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(isSelected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08))
                            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        // 탭이 적으면(대부분의 사용자) 스크롤·바운스가 생기지 않아 기존과 동일하게 보인다.
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }
}

/// Text and fill describe the same quantity; warning colors still represent actual usage.
@MainActor
struct LimitProgressBar: View {
    let usedPercent: Double
    let tint: Color
    @Environment(UsageStore.self) private var store

    var body: some View {
        ProgressView(value: min(100, max(0, store.limitDisplayPercent(usedPercent))), total: 100)
            .tint(tint)
            .controlSize(.small)
    }
}
