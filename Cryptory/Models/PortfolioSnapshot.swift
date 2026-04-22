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

struct PortfolioSummaryCardState: Equatable {
    let exchange: Exchange
    let totalAsset: Double
    let availableAsset: Double
    let lockedAsset: Double
    let totalPnl: Double
    let totalPnlPercent: Double

    init(snapshot: PortfolioSnapshot) {
        let totalPnl = snapshot.holdings.reduce(0) { $0 + $1.profitLoss }
        let investedAmount = snapshot.totalAsset - totalPnl
        let totalPnlPercent = investedAmount > 0 ? (totalPnl / investedAmount) * 100 : 0

        self.exchange = snapshot.exchange
        self.totalAsset = snapshot.totalAsset
        self.availableAsset = snapshot.availableAsset
        self.lockedAsset = snapshot.lockedAsset
        self.totalPnl = totalPnl
        self.totalPnlPercent = totalPnlPercent
    }
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
