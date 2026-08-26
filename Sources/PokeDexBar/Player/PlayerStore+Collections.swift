import Foundation

/// 컬렉션 — 배지는 도감에서 파생되고, 보상 있는 세트만 수령이 있다.
extension PlayerStore {
    struct CollectionStatus: Identifiable, Equatable {
        // `set` 이라는 이름은 계산 프로퍼티 본문에서 접근자 키워드로 파싱돼 컴파일이 깨진다.
        let collection: CollectionSet
        let done: Int
        let target: Int
        let claimed: Bool
        var id: String { collection.id }
        var completed: Bool { done >= target }
        /// 보상이 있고, 완성했고, 아직 안 받았다.
        var claimable: Bool { collection.rewards != nil && completed && !claimed }
    }

    func collectionStatuses() -> [CollectionStatus] {
        let dex = state.dex
        return CollectionCatalog.all.map { entry in
            let progress = CollectionCatalog.progress(of: entry, dex: dex)
            return CollectionStatus(collection: entry, done: progress.done,
                                    target: progress.target,
                                    claimed: state.claimedCollections.contains(entry.id))
        }
    }

    func canClaimCollection(_ collection: CollectionSet) -> Bool {
        collection.rewards != nil
            && !state.claimedCollections.contains(collection.id)
            && CollectionCatalog.completed(collection, dex: state.dex)
    }

    /// 보상을 받는다 — 지급은 미션과 같은 경로(`grant`)다.
    @discardableResult
    func claimCollection(_ collection: CollectionSet) -> Bool {
        guard canClaimCollection(collection), let rewards = collection.rewards else { return false }
        mutate { s in
            Self.grant(rewards, into: &s)
            s.claimedCollections.insert(collection.id)
        }
        return true
    }
}
