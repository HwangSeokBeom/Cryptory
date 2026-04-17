import Foundation

struct PortfolioSnapshot: Equatable {
    let exchange: Exchange
    let totalAsset: Double
    let availableAsset: Double
    let lockedAsset: Double
    let cash: Double
    let holdings: [Holding]
    let fetchedAt: Date?
    let isStale: Bool
    let partialFailureMessage: String?
}

struct PortfolioHistoryItem: Identifiable, Equatable {
    let id: String
    let exchange: Exchange
    let symbol: String
    let type: String
    let amount: Double
    let detail: String
    let occurredAt: Date?
    let status: String
}
