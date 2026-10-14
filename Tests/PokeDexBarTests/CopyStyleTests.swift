import XCTest
@testable import PokeDexBar

/// 한국어 조사 — 화면에 `이(가)` 가 그대로 나오면 안 된다. 포켓몬 이름은 데이터에서 오므로
/// 미리 정할 수 없고, 이름 하나 때문에 문장을 비틀 수도 없다.
final class JosaTests: XCTestCase {
    func testPicksByFinalConsonant() {
        XCTAssertEqual(Josa.iGa("피카츄"), "가")      // 받침 없음
        XCTAssertEqual(Josa.iGa("이브이"), "가")
        XCTAssertEqual(Josa.iGa("리자몽"), "이")      // ㅇ 받침
        XCTAssertEqual(Josa.iGa("잠만보"), "가")
        XCTAssertEqual(Josa.eulReul("리자몽"), "을")
        XCTAssertEqual(Josa.eulReul("피카츄"), "를")
        XCTAssertEqual(Josa.eunNeun("뮤츠"), "는")
    }

    /// 이름을 아직 못 받았을 때 쓰는 `#25` 도 문장 앞에 실제로 온다 — 숫자는 읽는 소리로 판단한다.
    func testNumbersUseTheirSpokenForm() {
        XCTAssertEqual(Josa.iGa("#25"), "가")         // 오
        XCTAssertEqual(Josa.iGa("#1"), "이")          // 일
        XCTAssertEqual(Josa.iGa("#3"), "이")          // 삼
        XCTAssertEqual(Josa.iGa("#6"), "이")          // 육
        XCTAssertEqual(Josa.iGa("#7"), "이")          // 칠
        XCTAssertEqual(Josa.iGa("#9"), "가")          // 구
    }

    /// ㄹ받침은 "로" 다 — 받침 유무만 보면 "천둥의돌으로"가 된다.
    func testTheRoParticleTreatsRieulAsNoFinalConsonant() {
        XCTAssertEqual(Josa.roEuro("천둥의돌"), "로")       // ㄹ
        XCTAssertEqual(Josa.roEuro("연결의끈"), "으로")     // ㄴ
        XCTAssertEqual(Josa.roEuro("딸기사탕공예"), "로")   // 받침 없음
        XCTAssertEqual(Josa.roEuro("#1"), "로")             // 일(ㄹ)
        XCTAssertEqual(Josa.roEuro("#7"), "로")             // 칠(ㄹ)
        XCTAssertEqual(Josa.roEuro("#8"), "로")             // 팔(ㄹ)
        XCTAssertEqual(Josa.roEuro("#3"), "으로")           // 삼(ㅁ)
        XCTAssertEqual(Josa.roEuro("#6"), "으로")           // 육(ㄱ)
        XCTAssertEqual(Josa.roEuro("#5"), "로")             // 오
    }

    func testEmptyAndForeignNamesDoNotCrash() {
        XCTAssertEqual(Josa.iGa(""), "가")
        XCTAssertEqual(Josa.iGa("Pikachu"), "가")
    }

    /// 실제 문구에 붙었는지 — 헬퍼만 있고 안 쓰면 화면은 그대로다.
    func testTheDiscoveryHeadlineUsesTheRightJosa() {
        XCTAssertTrue(L(.ko).discoveryFoundBy("피카츄", 2).hasPrefix("피카츄가"))
        XCTAssertTrue(L(.ko).discoveryFoundBy("리자몽", 1).hasPrefix("리자몽이"))
        XCTAssertTrue(L(.ko).formNeedsFusionPartner("제크로무").hasPrefix("제크로무가"))
    }

    /// 진화 버튼 문구가 **실제 도구 이름**에서 올바른 조사를 고르나 — 이 문장은 위 대표 문구
    /// 목록에 자동으로 안 들어와서, 조사가 틀려도 문체 테스트가 못 잡는다.
    func testTheEvolveWithButtonUsesTheRightParticle() {
        XCTAssertEqual(L(.ko).evolveWith(EvolutionItem.scrollOfWaters.label(.ko)), "물의 족자로 진화")
        XCTAssertEqual(L(.ko).evolveWith("천둥의돌"), "천둥의돌로 진화")     // ㄹ받침 → 로
        XCTAssertEqual(L(.ko).evolveWith("연결의끈"), "연결의끈으로 진화")
        XCTAssertEqual(L(.en).evolveWith("Scroll of Waters"), "Evolve with Scroll of Waters")
        // 모든 실제 도구 이름을 `roEuro` 와 직접 대조한다 — "로 진화" 접미사 검사는 "으로 진화" 도
        // 통과해 ㄹ 구분을 못 본다.
        for item in EvolutionItem.allCases {
            let name = item.label(.ko)
            XCTAssertEqual(L(.ko).evolveWith(name), "\(name)\(Josa.roEuro(name)) 진화")
        }
    }
}

/// 문체 — 이 앱의 한국어는 **해요체**다. 한 화면에서 "물어 옵니다"와 "살 수 있어요"가 섞이면
/// 두 사람이 쓴 것처럼 읽힌다. 문구를 더할 때 조용히 어긋나는 걸 사람 눈으로만 잡을 수는 없다.
final class KoreanToneTests: XCTestCase {
    /// 모든 한국어 문구를 훑는다 — 새 문구가 늘어도 자동으로 대상에 들어온다.
    private var allKorean: [(key: String, text: String)] {
        let l = L(.ko)
        var out: [(String, String)] = []
        // 인자 없는 문구는 Mirror 로 못 잡는다(계산 프로퍼티) — 대신 대표 문구를 명시한다.
        // 여기 목록이 곧 "문체를 지키기로 한 문장들"이다.
        out.append(("bagEmptyHint", l.bagEmptyHint))
        out.append(("shopEvolutionHint", l.shopEvolutionHint))
        out.append(("tamperedExplanation", l.tamperedExplanation))
        out.append(("allOffHint", l.allOffHint))
        out.append(("starterPickerSubtitle", l.starterPickerSubtitle))
        out.append(("limitRefreshRateLimited", l.limitRefreshRateLimited))
        out.append(("limitRefreshNoCredential", l.limitRefreshNoCredential))
        out.append(("claudeAuthExpiredHint", l.claudeAuthExpiredHint))
        out.append(("disableKeychainHint", l.disableKeychainHint))
        out.append(("evolutionLockedHint", l.evolutionLockedHint))
        out.append(("ribbonForageDone", l.ribbonForageDone))
        out.append(("detailPartnerOnlyExp", l.detailPartnerOnlyExp))
        return out
    }

    func testNoFormalStyleLeaksIn() {
        for (key, text) in allKorean {
            XCTAssertFalse(text.contains("니다"),
                           "\(key) 가 합니다체다 — 이 앱은 해요체다: \(text)")
        }
    }

    /// 조사를 문구에 박아 두면 화면에 괄호가 그대로 나온다.
    func testNoHardcodedJosaAnywhere() {
        for (key, text) in allKorean {
            for bad in ["이(가)", "을(를)", "은(는)"] {
                XCTAssertFalse(text.contains(bad), "\(key) 에 \(bad) 가 박혀 있다")
            }
        }
    }
}

/// 이름은 원작 표기를 따른다 — 팬 번역이나 직역이 섞이면 검색도 안 되고 어색하다.
final class ItemNamingTests: XCTestCase {
    func testMaxMushroomUsesTheOfficialNames() {
        XCTAssertEqual(ShopItem.dynamaxMushroom.label(.ko), "다이버섯")
        XCTAssertEqual(ShopItem.dynamaxMushroom.label(.en), "Max Mushroom")
        XCTAssertEqual(ShopItem.dynamaxMushroom.label(.ja), "ダイマックスウキノコ")
    }

    /// 세 언어가 모두 채워져 있어야 한다 — 하나라도 비면 그 언어 화면에 빈칸이 남는다.
    func testEveryItemIsNamedInEveryLanguage() {
        for lang in AppLanguage.allCases {
            for item in ShopItem.allCases { XCTAssertFalse(item.label(lang).isEmpty, "\(item)") }
            for item in EvolutionItem.allCases { XCTAssertFalse(item.label(lang).isEmpty, "\(item)") }
            for item in FormItem.allCases { XCTAssertFalse(item.label(lang).isEmpty, "\(item)") }
        }
    }
}
