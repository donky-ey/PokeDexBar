import Foundation

/// **진화할 때 쓴 도구가 정하는 겉모습.** 부화 때 정해지는 `BirthFormCatalog` 와 성질이 같고
/// (키로 저장, 평생 고정, 되돌릴 수 없음) 정해지는 **시점만** 다르다. 그래서 저장도 같은 자리
/// (`Individual.fixedForm`)를 쓴다.
///
/// 전 540체인 전수 확인(2026-10-12): 도구가 결과 모습을 가르는 간선은 **둘뿐이다**(쿠푸 → 우라오스,
/// 마빌크 → 마휘핑). 이 파일에는 지금 우라오스만 있다.
///
/// **기본형 쪽은 키를 안 박는다** — "후보 없음이 곧 기본형"이라, 그래야 도감 키가
/// `892` / `892/urshifu-rapidstrike` 로 자연스럽게 갈린다.
enum EvolvedFormCatalog {
    struct Decided: Sendable, Equatable {
        let speciesID: Int
        let item: EvolutionItem
        /// nil 이면 기본형 — 키를 안 박는다.
        let variant: String?
        /// 변종일 때의 Showdown 슬러그. 기본형이면 nil.
        let slug: String?
        let label: FormLabel?
    }

    static let all: [Decided] = [
        .init(speciesID: 892, item: .scrollOfDarkness, variant: nil, slug: nil, label: nil),
        .init(speciesID: 892, item: .scrollOfWaters, variant: "rapidstrike",
              slug: "urshifu-rapidstrike",
              label: .init("연격의 태세", "Rapid Strike Style", "れんげきのかた")),
    ]

    static func variant(speciesID: Int, item: EvolutionItem) -> String? {
        all.first { $0.speciesID == speciesID && $0.item == item }?.variant
    }

    static func form(speciesID: Int, variant: String) -> (slug: String, label: FormLabel)? {
        guard let hit = all.first(where: { $0.speciesID == speciesID && $0.variant == variant }),
              let slug = hit.slug, let label = hit.label else { return nil }
        return (slug, label)
    }

    /// 두 카탈로그의 키 충돌을 보는 색인(테스트)이자, `Individual.sanitized()` 가 "이 변종은
    /// 그 종이 가질 수 있는가"를 묻는 자리.
    static var variantsBySpecies: [Int: [String]] {
        Dictionary(grouping: all.compactMap { d in d.variant.map { (d.speciesID, $0) } },
                   by: \.0).mapValues { $0.map(\.1) }
    }
}
