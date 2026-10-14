import XCTest
@testable import PokeDexBar

/// 도구 이름은 **공식 이름표가 단일 소스다.** 기억으로 적으면 조용히 어긋난다 — 실측으로 109개 중
/// 87개가 달랐다(번개의돌→천둥의돌, 생크림→휘핑팝, 유석→운석, 백금옥→큰백금옥, 불꽃메모리→
/// 파이어메모리 …). 사람 눈으로 잡히는 종류가 아니다: 틀린 이름도 그럴듯하게 읽히고, 화면에
/// 띄워 놓고 봐도 "원래 저런가" 싶다.
///
/// 그래서 `scripts/generate-item-names.py` 가 PokéAPI 에서 공식 ko/en/ja 를 받아 픽스처로
/// 커밋하고, 이 테스트가 앱 라벨을 그 픽스처와 대조한다. **테스트는 네트워크를 안 탄다** —
/// test-gate 는 오프라인이어야 하므로 받아 둔 것만 본다. 도구를 더하거나 이름을 손으로 고치면
/// 여기서 깨진다.
final class ItemNameTests: XCTestCase {
    private struct Fixture: Decodable {
        let official: [String: [String: String]]
        let invented: [String]
        let forms: [String: [String: String]]
    }

    private func fixture() throws -> Fixture {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "official-item-names", withExtension: "json",
                              subdirectory: "ItemNames"),
            "픽스처가 없다 — Package.swift 의 resources 에 Fixtures/ItemNames 가 있는지 보라")
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    /// 앱 키 → (ko, en, ja). 두 enum 을 한 표로 합쳐 본다 — 라벨이 어느 enum 에 살든 규칙은 같다.
    private func appLabels() -> [String: (String, String, String)] {
        var out: [String: (String, String, String)] = [:]
        for item in EvolutionItem.allCases {
            out[item.rawValue] = (item.label(.ko), item.label(.en), item.label(.ja))
        }
        for item in FormItem.allCases {
            out[item.rawValue] = (item.label(.ko), item.label(.en), item.label(.ja))
        }
        return out
    }

    /// **업스트림이 틀린 자리.** 값은 "지금 PokéAPI 가 이렇게 돌려준다"는 기록이다 — 공식이
    /// 고쳐지면 아래 `testTheUpstreamQuirksAreStillWrong` 이 깨져서 예외를 걷어낼 때를 알려 준다.
    /// 예외를 영구 면제로 두면 "한 번도 발동한 적 없는 가드"와 같은 장식이 된다.
    ///
    /// - `linking-cord` ja: 선행 공백이 섞여 있다(` つながりのヒモ`) — 표기 결함.
    /// - `masterpiece-teacup` ja: `ボンサクのちゃわん`(凡作 = 범작)을 돌려준다. 범작찻잔의 이름과
    ///   같아 둘이 구분되지 않는다. 걸작은 `ケッサク`(傑作)다.
    /// - `up-grade` en: 원작 품목명은 하이픈이 있는 `Up-Grade` 다.
    private static let upstreamQuirks: [String: [AppLanguage: String]] = [
        "linking-cord": [.ja: " つながりのヒモ"],
        "masterpiece-teacup": [.ja: "ボンサクのちゃわん"],
        "up-grade": [.en: "Upgrade"],
    ]

    private static func label(_ labels: (String, String, String), _ lang: AppLanguage) -> String {
        switch lang { case .ko: labels.0; case .en: labels.1; case .ja: labels.2 }
    }

    /// 모든 라벨이 공식 이름과 같아야 한다 — 업스트림 결함으로 기록한 자리만 빼고.
    func testEveryLabelMatchesTheOfficialName() throws {
        let official = try fixture().official
        let app = appLabels()
        for (key, names) in official.sorted(by: { $0.key < $1.key }) {
            let labels = try XCTUnwrap(app[key], "\(key) 라벨이 없다")
            for lang in AppLanguage.allCases {
                let code = switch lang { case .ko: "ko"; case .en: "en"; case .ja: "ja" }
                guard let want = names[code] else { continue }
                if Self.upstreamQuirks[key]?[lang] != nil { continue }
                XCTAssertEqual(Self.label(labels, lang), want,
                               "\(key) \(code) 이 공식 이름과 다르다")
            }
        }
    }

    /// 예외는 **여전히 예외여야 한다.** 공식이 고쳐졌으면 이 테스트가 깨지고, 그때 예외를 지운다.
    func testTheUpstreamQuirksAreStillWrong() throws {
        let official = try fixture().official
        let app = appLabels()
        for (key, byLang) in Self.upstreamQuirks {
            let names = try XCTUnwrap(official[key], "\(key) 가 픽스처에 없다 — 예외가 낡았다")
            let labels = try XCTUnwrap(app[key])
            for (lang, upstream) in byLang {
                let code = switch lang { case .ko: "ko"; case .en: "en"; case .ja: "ja" }
                XCTAssertEqual(names[code], upstream,
                               "\(key) \(code) 의 공식 값이 바뀌었다 — 예외를 다시 판단하라")
                XCTAssertNotEqual(Self.label(labels, lang), upstream,
                                  "\(key) \(code) 이 업스트림 결함을 그대로 베꼈다")
            }
        }
    }

    /// 새 도구를 더하고 생성 스크립트를 안 돌리면 여기서 걸린다 — 공식 이름이 있는지 없는지
    /// 둘 중 하나로 **명시**돼 있어야 한다(`invented` 는 원작에 아이템이 없다는 기록이다).
    func testEveryItemIsEitherOfficialOrDeclaredInvented() throws {
        let f = try fixture()
        let declared = Set(f.official.keys).union(f.invented)
        for key in appLabels().keys.sorted() {
            XCTAssertTrue(declared.contains(key),
                          "\(key) 가 픽스처에 없다 — scripts/generate-item-names.py 를 돌려라")
        }
    }

    /// 픽스처에 앱에 없는 키가 남아 있으면 도구를 지우고 픽스처를 안 갱신한 것이다.
    func testTheFixtureHasNoStaleKeys() throws {
        let f = try fixture()
        let app = Set(appLabels().keys)
        for key in Set(f.official.keys).union(f.invented).sorted() {
            XCTAssertTrue(app.contains(key),
                          "\(key) 가 앱에 없다 — scripts/generate-item-names.py 를 돌려라")
        }
    }

    /// 폼 이름도 공식 이름표에서 온다 — 도구 이름 87개가 틀렸던 것과 같은 부류다.
    /// en 은 대조하지 않는다: PokéAPI 는 두 축을 합친 이름("Ruby Cream Strawberry Sweet")을 주는데
    /// 이 앱의 폼은 크림만 가리킨다(생성 스크립트의 `FORM_LANGS`). 공식에 없는 언어는 건너뛴다.
    func testEveryEvolvedFormLabelMatchesTheOfficialName() throws {
        let official = try fixture().forms
        for decided in EvolvedFormCatalog.all {
            guard let slug = decided.slug, let label = decided.label else { continue }
            guard let names = official[slug] else {
                return XCTFail("\(slug) 가 픽스처에 없다 — scripts/generate-item-names.py 를 돌려라")
            }
            if let ko = names["ko"] { XCTAssertEqual(label.ko, ko, slug) }
            if let en = names["en"] { XCTAssertEqual(label.en, en, slug) }
            if let ja = names["ja"] { XCTAssertEqual(label.ja, ja, slug) }
        }
    }
}
