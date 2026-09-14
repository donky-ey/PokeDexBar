import XCTest
@testable import PokeDexBar

final class ShopViewTests: XCTestCase {
    /// 확률은 숨기지 않는다 — 표기 문자열을 테스트로 잠근다.
    func testOddsTextListsEveryGrade() {
        let text = EggSlotsView.oddsText(.ko)
        XCTAssertTrue(text.contains("커먼 60%"), text)
        XCTAssertTrue(text.contains("레어 22%"), text)
        XCTAssertTrue(text.contains("에픽 16%"), text)
        // 레전더리 3% → 2% — 도감 미션의 확정권 11장과 맞바꾼 억제(`EggBalance.odds` 참고).
        XCTAssertTrue(text.contains("레전더리 2%"), text)
    }

    /// 표기 확률의 합은 100% 여야 한다 — 밸런스를 고치면 문구도 같이 틀어지는 걸 막는다.
    func testOddsSumToOne() {
        let total = EggBalance.odds.reduce(0) { $0 + $1.probability }
        XCTAssertEqual(total, 1.0, accuracy: 0.0001)
    }
}

/// 뽑기 착지 — 실패를 삼키지 않는지. 후보를 받아오는 동안에도 슬롯·아이템 버튼이 살아 있어
/// 지갑이 뽑기 값 아래로 내려갈 수 있고, 그때 `startEgg` 이 돌려주는 nil 을 버리면 사용자에겐
/// 아무 일도 안 일어난다(재화도 그대로, 알도 없음, 안내도 없음).
@MainActor
final class ShopDrawLandingTests: XCTestCase {
    private func makeStore(wallet: Int, slots: Int = 3, eggs: Int = 0) -> PlayerStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("shop-draw-\(UUID().uuidString).json")
        let store = PlayerStore(fileURL: url, rng: SeededRNG(seed: 1),
                                now: { Date(timeIntervalSince1970: 0) })
        store.seedForTesting(wallet: wallet, slots: slots, eggs: eggs,
                             at: Date(timeIntervalSince1970: 0))
        return store
    }

    func testSuccessfulDrawReportsNoError() {
        let store = makeStore(wallet: EggBalance.drawPrice)
        XCTAssertNil(EggSlotsView.landDraw(store, grade: .common, speciesID: 1, shiny: false))
        XCTAssertEqual(store.state.eggs.count, 1)
    }

    /// 조회를 기다리는 사이 지갑이 값 아래로 내려간 경우 — 조용한 무동작 대신 안내가 나와야 한다.
    func testDrawThatCannotLandReportsLocalizedError() {
        let store = makeStore(wallet: EggBalance.drawPrice - 1)
        XCTAssertEqual(EggSlotsView.landDraw(store, grade: .common, speciesID: 1, shiny: false),
                       store.l.shopDrawUnavailable)
        XCTAssertTrue(store.state.eggs.isEmpty)
    }

    /// 슬롯이 다 찬 경우도 같은 안내 — 지갑만이 착지 실패 사유가 아니다.
    func testDrawWithNoFreeSlotReportsLocalizedError() {
        let store = makeStore(wallet: 100_000_000_000, slots: 3, eggs: 3)
        XCTAssertNotNil(EggSlotsView.landDraw(store, grade: .common, speciesID: 1, shiny: false))
    }

    /// 안내는 세 언어 모두 있어야 한다(빈 문자열·미번역 방지).
    func testDrawUnavailableIsLocalized() {
        let texts = [AppLanguage.ko, .en, .ja].map { L($0).shopDrawUnavailable }
        XCTAssertEqual(Set(texts).count, 3, texts.description)
        XCTAssertFalse(texts.contains { $0.isEmpty })
    }
}

/// 뽑기가 부화칸으로 옮겨 갔다 — 결과가 놓이는 자리에서 뽑는다.
@MainActor
final class DrawLocationTests: XCTestCase {
    private func code(_ file: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/PokeDexBar/UI/\(file)")
        let text = try String(contentsOf: url, encoding: .utf8)
        // 주석을 먼저 걷어낸다 — 통짜 검색은 바로 위 주석의 같은 낱말에 걸린다.
        return text.split(separator: "\n")
            .map { $0.contains("//") ? String($0[..<$0.range(of: "//")!.lowerBound]) : String($0) }
            .joined(separator: "\n")
    }

    /// **뽑기는 부화칸에만 있다.** 상점에 남아 있으면 두 곳이 되어 하나만 고쳐진다 —
    /// 오늘의 목표를 옮길 때와 같은 가드다.
    func testDrawingLivesWithTheSlotsAndNotInTheShop() throws {
        let slots = try code("EggSlotsView.swift")
        XCTAssertTrue(slots.contains("func draw()"), "부화칸이 뽑기를 안 들고 있다")
        XCTAssertTrue(slots.contains("EggRevealView("), "연출이 결과가 놓이는 자리에서 안 난다")
        let shop = try code("ShopTabView.swift")
        XCTAssertFalse(shop.contains("func draw()"), "상점에 뽑기가 남아 있다")
        XCTAssertFalse(shop.contains("EggRevealView("), "상점에 뽑기 연출이 남아 있다")
    }

    /// **확정권도 같이 왔다.** 개봉은 늘 알이 태어나는 자리에서 일어나야 한다.
    func testTicketsMovedWithTheDraw() throws {
        XCTAssertTrue(try code("EggSlotsView.swift").contains("drawWithTicket("))
        XCTAssertFalse(try code("ShopTabView.swift").contains("drawWithTicket("))
    }

    /// **슬롯 확장은 상점에 남는다**(사용자 결정) — 평생 두세 번 하는 구매라 사는 곳이 맞다.
    /// 대조군이 없으면 "슬롯에 관한 걸 전부 옮겼다" 도 위를 통과한다.
    func testBuyingASlotStaysInTheShop() throws {
        XCTAssertTrue(try code("ShopTabView.swift").contains("slotSection"))
        XCTAssertFalse(try code("EggSlotsView.swift").contains("buySlot("))
    }

    /// 뽑을 수 있는지는 **스토어 하나**가 정한다 — 화면이 조건을 따로 적으면 갈린다.
    func testTheTileFollowsTheStoreGate() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("draw-\(UUID().uuidString).json")
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let store = PlayerStore(fileURL: url, rng: SeededRNG(seed: 2), now: { now })

        store.seedForTesting(wallet: EggBalance.drawPrice - 1, slots: 3, eggs: 0, at: now)
        XCTAssertFalse(store.canDraw, "지갑이 모자란데 뽑을 수 있다")
        store.seedForTesting(wallet: EggBalance.drawPrice, slots: 3, eggs: 3, at: now)
        XCTAssertFalse(store.canDraw, "빈 칸이 없는데 뽑을 수 있다")
        store.seedForTesting(wallet: EggBalance.drawPrice, slots: 3, eggs: 0, at: now)
        XCTAssertTrue(store.canDraw)
    }
}
