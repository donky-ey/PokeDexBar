import XCTest
@testable import PokeDexBar

/// 세대 확정권 — 그 세대의 종만 나온다.
final class GenerationTicketTests: XCTestCase {
    /// 실제 인덱스를 흉내 낸 후보 목록. 세대마다 여러 마리, 등급도 섞여 있다.
    /// `BaseSpecies` 의 실제 생성자를 쓴다 — 손으로 만든 모양은 증거가 아니다.
    private func index() -> [BaseSpecies] {
        // 각 세대의 첫 종과 마지막 종, 그리고 그 세대의 전설 하나씩.
        let ids = [1, 151, 152, 251, 252, 386, 387, 493, 494, 649,
                   650, 721, 722, 809, 810, 905, 906, 1025]
        return ids.map { BaseSpecies(id: $0, captureRate: 45, isLegendary: false, isMythical: false) }
    }

    func testEveryGenerationFiltersToItsOwnRange() {
        for generation in 1...9 {
            let range = DexMissions.generations[generation]!
            let filtered = EggBalance.speciesIndex(index(), inGeneration: generation)
            XCTAssertFalse(filtered.isEmpty, "\(generation)세대 후보가 비었다")
            for species in filtered {
                XCTAssertTrue(range.contains(species.id),
                              "\(generation)세대 티켓이 \(species.id) 를 냈다")
            }
        }
    }

    /// 거르고 나서 뽑아도 그 세대 안이다 — 거르기와 선택을 이어 붙였을 때가 진짜 질문이다.
    func testPickingFromAFilteredIndexStaysInTheGeneration() {
        for generation in 1...9 {
            let range = DexMissions.generations[generation]!
            let filtered = EggBalance.speciesIndex(index(), inGeneration: generation)
            for step in 0..<50 {
                let picked = EggBalance.pickSpecies(from: filtered, grade: .common,
                                                    roll: Double(step) / 50)
                XCTAssertTrue(range.contains(picked),
                              "\(generation)세대에서 \(picked) 가 나왔다")
            }
        }
    }

    /// 대조군: 안 거른 인덱스는 범위 밖도 낸다. 없으면 "거르기가 아무것도 안 해도" 위가 통과한다.
    func testAnUnfilteredIndexDoesLeaveTheGeneration() {
        let range = DexMissions.generations[1]!
        let picks = (0..<50).map {
            EggBalance.pickSpecies(from: index(), grade: .common, roll: Double($0) / 50)
        }
        XCTAssertTrue(picks.contains { !range.contains($0) },
                      "안 거른 인덱스가 1세대만 냈다 — 이 비교는 아무것도 못 잡는다")
    }

    /// 아홉 세대가 전부 도달 가능하다 — 한 세대라도 빈 목록이면 그 티켓이 죽은 티켓이다.
    func testNoGenerationIsEmpty() {
        for generation in 1...9 {
            XCTAssertFalse(EggBalance.speciesIndex(index(), inGeneration: generation).isEmpty,
                           "\(generation)세대")
        }
    }

    /// 없는 세대는 빈 목록 — 호출부가 그걸로 "티켓이 이상하다"를 판단한다.
    func testAnUnknownGenerationFiltersToNothing() {
        XCTAssertTrue(EggBalance.speciesIndex(index(), inGeneration: 0).isEmpty)
        XCTAssertTrue(EggBalance.speciesIndex(index(), inGeneration: 10).isEmpty)
    }

    /// 확정권 목록을 뷰가 손으로 나열하지 않는다 — 나열하면 새 확정권이 조용히 안 보인다.
    func testTheTicketRowIsDerivedNotHandListed() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/PokeDexBar/UI/EggSlotsView.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        // 주석을 먼저 걷어낸다 — 통짜 검색은 바로 위 주석의 같은 낱말에 걸린다.
        let code = source.split(separator: "\n")
            .map { $0.contains("//") ? String($0[..<$0.range(of: "//")!.lowerBound]) : String($0) }
            .joined(separator: "\n")
        XCTAssertFalse(code.contains("[ShopItem.rareEggTicket"), "확정권을 손으로 나열하고 있다")
        XCTAssertTrue(code.contains("guaranteedGeneration != nil"), "세대권이 목록에 안 든다")
    }
}
