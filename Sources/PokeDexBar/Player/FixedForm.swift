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
}
