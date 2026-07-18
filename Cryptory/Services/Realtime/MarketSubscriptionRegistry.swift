import Foundation

/// Reference-counted ownership of upstream market subscriptions.
///
/// Multiple consumers may own the same `PublicMarketSubscription`; the engine
/// sends one upstream `subscribe` when the first owner arrives and one
/// `unsubscribe` when the last owner leaves. Owned and mutated only by
/// `MarketStreamEngine`.
struct MarketSubscriptionRegistry {
    /// Net upstream effect of a registry mutation.
    struct Diff: Equatable {
        var subscribe: Set<PublicMarketSubscription> = []
        var unsubscribe: Set<PublicMarketSubscription> = []

        var isEmpty: Bool { subscribe.isEmpty && unsubscribe.isEmpty }
    }

    private var owners: [PublicMarketSubscription: Set<UUID>] = [:]

    var activeSubscriptions: Set<PublicMarketSubscription> {
        Set(owners.keys)
    }

    var isEmpty: Bool { owners.isEmpty }

    var subscriptionCount: Int { owners.count }

    /// Total (owner, subscription) ownership pairs across all consumers.
    var totalOwnershipCount: Int {
        owners.values.reduce(0) { $0 + $1.count }
    }

    /// Replaces `owner`'s entire subscription set, returning the net upstream
    /// subscribe/unsubscribe requirement. Rapid successive replacements
    /// converge because each call fully reconciles against current ownership.
    mutating func replace(
        owner: UUID,
        with newSubscriptions: Set<PublicMarketSubscription>
    ) -> Diff {
        var diff = Diff()
        let previous = ownedSubscriptions(of: owner)

        for subscription in previous.subtracting(newSubscriptions) {
            if release(owner: owner, subscription: subscription) {
                diff.unsubscribe.insert(subscription)
            }
        }
        for subscription in newSubscriptions.subtracting(previous) {
            if acquire(owner: owner, subscription: subscription) {
                diff.subscribe.insert(subscription)
            }
        }
        return diff
    }

    /// Removes every subscription owned by `owner`, returning subscriptions
    /// whose last owner just left (requiring an upstream unsubscribe).
    mutating func removeOwner(_ owner: UUID) -> Set<PublicMarketSubscription> {
        var released: Set<PublicMarketSubscription> = []
        for subscription in ownedSubscriptions(of: owner) {
            if release(owner: owner, subscription: subscription) {
                released.insert(subscription)
            }
        }
        return released
    }

    func ownedSubscriptions(of owner: UUID) -> Set<PublicMarketSubscription> {
        Set(owners.filter { $0.value.contains(owner) }.keys)
    }

    /// Returns true when this acquisition requires an upstream subscribe.
    private mutating func acquire(owner: UUID, subscription: PublicMarketSubscription) -> Bool {
        let isFirstOwner = owners[subscription, default: []].isEmpty
        owners[subscription, default: []].insert(owner)
        return isFirstOwner
    }

    /// Returns true when this release requires an upstream unsubscribe.
    private mutating func release(owner: UUID, subscription: PublicMarketSubscription) -> Bool {
        guard var current = owners[subscription], current.contains(owner) else { return false }
        current.remove(owner)
        if current.isEmpty {
            owners.removeValue(forKey: subscription)
            return true
        }
        owners[subscription] = current
        return false
    }
}
