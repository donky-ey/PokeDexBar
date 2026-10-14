import Foundation

/// 고정 변종 키 → 그 단계의 겉모습. **두 카탈로그를 여기서만 묻는다** — 그리는 자리
/// (`Individual.spriteForm`)·도감 키(`DexKey`)·배지(`birthFormLabel`) 셋이 각각 카탈로그를
/// 직접 부르면 카탈로그가 늘 때마다 분기가 셋씩 는다.
enum FixedForm {
    static func resolve(speciesID: Int, variant: String) -> (slug: String, label: FormLabel)? {
        if let born = BirthFormCatalog.form(speciesID: speciesID, variant: variant) {
            return (born.slug, born.label)
        }
        return EvolvedFormCatalog.form(speciesID: speciesID, variant: variant)
    }

    /// 이 종이 가질 수 있는 고정 변종 전부 — **두 카탈로그를 한 번에.** `resolve` 가 "이 키가
    /// 무엇인가"를 묻는 자리라면 이건 "무엇이 있을 수 있나"를 묻는 자리다(도감 행·신뢰경계).
    /// 둘을 따로 부르면 새 카탈로그를 더할 때 도감이 그 변종을 모르는 채로 남는다 — 진화로
    /// 정해진 도감 키가 디코드 때 유령 키로 지워졌던 결함이 정확히 이것이다.
    ///
    /// `replacesBase` 는 부화 카탈로그 종이다 — 원종 행이 따로 없고 변종이 그 자리를 채운다
    /// (안농 A·화원 비비용). 진화로 정해지는 종은 기본형(키 없음)이 여전히 한 행이다.
    static func forms(speciesID: Int)
        -> (rows: [(slug: String, label: FormLabel)], replacesBase: Bool) {
        let born = BirthFormCatalog.forms(speciesID: speciesID)
        if !born.isEmpty { return (born.map { ($0.slug, $0.label) }, true) }
        return (EvolvedFormCatalog.forms(speciesID: speciesID), false)
    }
}
