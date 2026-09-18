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

    /// `EggSlotsView.swift` 의 주석을 걷어낸 소스. 통짜 `contains(...)` 는 바로 위 주석의
    /// 같은 낱말에 걸려 코드가 지워져도 통과하므로, 아래 두 소스 검증 테스트가 공유해서 쓴다.
    private static func eggSlotsViewCode() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/PokeDexBar/UI/EggSlotsView.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        return source.split(separator: "\n")
            .map { $0.contains("//") ? String($0[..<$0.range(of: "//")!.lowerBound]) : String($0) }
            .joined(separator: "\n")
    }

    /// 확정권 목록을 뷰가 손으로 나열하지 않는다 — 나열하면 새 확정권이 조용히 안 보인다.
    func testTheTicketRowIsDerivedNotHandListed() throws {
        let code = try Self.eggSlotsViewCode()
        XCTAssertFalse(code.contains("[ShopItem.rareEggTicket"), "확정권을 손으로 나열하고 있다")
        XCTAssertTrue(code.contains("guaranteedGeneration != nil"), "세대권이 목록에 안 든다")
    }

    /// 세대권은 메타몽 위장을 타면 안 된다. 메타몽(132)은 1세대라, 9세대권이 메타몽을 내면 그
    /// 티켓이 스스로 한 "이 세대만" 약속을 깬다. 위장 굴림 자체(`DittoDisguise.hits`)는 등급만
    /// 보고 세대를 모르므로, `drawWithTicket` 이 `ticket.guaranteedGeneration == nil` 로 그
    /// 호출을 막고 있는지를 소스에서 확인한다 — `drawWithTicket` 은 뷰의 private 비동기 메서드라
    /// 여기서 직접 부를 수 없다(이 파일의 다른 소스 검증 테스트와 같은 이유).
    func testGenerationTicketsGateOutTheDittoDisguise() throws {
        let code = try Self.eggSlotsViewCode()
        guard let funcRange = code.range(of: "private func drawWithTicket") else {
            XCTFail("drawWithTicket 을 못 찾았다")
            return
        }
        let body = code[funcRange.lowerBound...]
        guard let hitsRange = body.range(of: "DittoDisguise.hits") else {
            XCTFail("DittoDisguise.hits 호출이 drawWithTicket 에서 사라졌다 — 등급권의 위장이 없어졌다")
            return
        }
        let before = body[..<hitsRange.lowerBound]
        XCTAssertTrue(before.contains("ticket.guaranteedGeneration == nil"),
                      "세대권이 메타몽 위장을 걸러내는 게이트가 drawWithTicket 에 없다")
    }

    /// 대조군 — 등급권(세대 제한이 없는 확정권)은 게이트를 그대로 통과한다. 위 테스트가 "항상
    /// 막는" 조건으로 몰래 바뀌어도(예: `true &&`) 안 잡히는 것을 막는다. 위장 굴림 자체도 여전히
    /// 살아 있다 — 이 조건이 전부 사라지면(`hits` 삭제) 이 테스트가 대신 걸린다.
    func testGradeTicketsStillPassTheDittoGate() {
        for ticket in [ShopItem.rareEggTicket, .epicEggTicket, .legendaryEggTicket] {
            XCTAssertNil(ticket.guaranteedGeneration,
                        "\(ticket) 가 세대를 갖고 있다 — 대조군 전제가 깨졌다")
        }
        XCTAssertTrue(DittoDisguise.hits(grade: .common, roll: 0),
                      "커먼 + roll 0 인데도 위장이 안 걸린다 — 등급권이 닿을 위장 자체가 죽었다")
    }
}
