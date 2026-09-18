import XCTest
@testable import PokeDexBar

/// 박사의 상자 화면 — 자리와 안내 문구.
@MainActor
final class ProfessorBoxViewTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeStore() -> PlayerStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("box-\(UUID().uuidString).json")
        let store = PlayerStore(fileURL: url, rng: SeededRNG(seed: 3), now: { self.now })
        store.seedForTesting(wallet: 0, slots: 3, eggs: 0, at: now)
        return store
    }

    /// 상자는 **박사 구역 아래**에 선다 — 포인트를 주는 곳과 쓰는 곳이 떨어져 있으면
    /// 포인트가 무엇에 쓰이는지 알 길이 없다.
    func testTheBoxSitsUnderTheProfessorSections() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/PokeDexBar/UI/ShopTabView.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        let code = source.split(separator: "\n")
            .map { $0.contains("//") ? String($0[..<$0.range(of: "//")!.lowerBound]) : String($0) }
            .joined(separator: "\n")
        let offer = try XCTUnwrap(code.range(of: "ProfessorOfferSection("))
        let goals = try XCTUnwrap(code.range(of: "DailyGoalsView("))
        let box = try XCTUnwrap(code.range(of: "ProfessorBoxSection("))
        XCTAssertLessThan(offer.lowerBound, box.lowerBound, "상자가 제안보다 위에 있다")
        XCTAssertLessThan(goals.lowerBound, box.lowerBound, "상자가 의뢰보다 위에 있다")
    }

    /// 무료 판이 남았으면 그렇게 말한다.
    func testTheFreeDrawIsAnnounced() {
        let store = makeStore()
        XCTAssertEqual(ProfessorBoxSection.footnote(store: store), store.l.itemDrawFreeToday)
    }

    /// 포인트가 모자라면 **왜 못 누르는지** 말한다 — 회색 버튼만 두고 이유를 안 적어
    /// 사용자가 물어볼 곳이 없던 전례가 있다.
    func testAShortWalletSaysWhy() {
        let store = makeStore()
        _ = store.drawItem()                      // 무료 소진
        XCTAssertEqual(ProfessorBoxSection.footnote(store: store),
                       store.l.itemDrawNeedsPoints(20))
    }

    /// 살 수 있으면 값이 아니라 다음 값을 알려 준다 — 대조군. 없으면 "늘 이유만 낸다"도 통과한다.
    func testWithEnoughPointsItShowsThePrice() {
        let store = makeStore()
        store.grantPointsForTesting(1000)
        _ = store.drawItem()
        XCTAssertEqual(ProfessorBoxSection.footnote(store: store), store.l.itemDrawPrice(20))
    }
}
