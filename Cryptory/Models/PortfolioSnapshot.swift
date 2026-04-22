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

struct PortfolioOverviewCardState: Equatable {
    let totalAsset: Double
    let availableAsset: Double
    let lockedAsset: Double
    let cash: Double
    let totalPnl: Double
    let totalPnlPercent: Double
    let exchangeCount: Int
}

struct PortfolioAllocationRowState: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let amount: Double
    let percent: Double
    let tintHex: String
}

struct PortfolioHoldingRowState: Identifiable, Equatable {
    let id: String
    let exchange: Exchange
    let symbol: String
    let name: String
    let totalQuantity: Double
    let availableQuantity: Double
    let lockedQuantity: Double
    let averageBuyPrice: Double
    let evaluationAmount: Double
    let profitLoss: Double
    let profitLossRate: Double
    let weightPercent: Double

    init(holding: Holding, exchange: Exchange, totalPortfolioValue: Double) {
        self.id = "\(exchange.rawValue)-\(holding.symbol)"
        self.exchange = exchange
        self.symbol = holding.symbol
        self.name = CoinCatalog.coin(symbol: holding.symbol).name
        self.totalQuantity = holding.totalQuantity
        self.availableQuantity = holding.availableQuantity
        self.lockedQuantity = holding.lockedQuantity
        self.averageBuyPrice = holding.averageBuyPrice
        self.evaluationAmount = holding.evaluationAmount
        self.profitLoss = holding.profitLoss
        self.profitLossRate = holding.profitLossRate
        self.weightPercent = Self.weightPercent(amount: holding.evaluationAmount, total: totalPortfolioValue)
    }

    private static func weightPercent(amount: Double, total: Double) -> Double {
        guard total > 0 else { return 0 }
        return (amount / total) * 100
    }
}

struct ExchangePortfolioSectionViewState: Identifiable, Equatable {
    var id: String { exchange.rawValue }

    let exchange: Exchange
    let totalAsset: Double
    let availableAsset: Double
    let lockedAsset: Double
    let cash: Double
    let assetCount: Int
    let weightPercent: Double
    let holdings: [PortfolioHoldingRowState]
    let partialFailureMessage: String?

    init(snapshot: PortfolioSnapshot, totalPortfolioValue: Double) {
        self.exchange = snapshot.exchange
        self.totalAsset = snapshot.totalAsset
        self.availableAsset = snapshot.availableAsset
        self.lockedAsset = snapshot.lockedAsset
        self.cash = snapshot.cash
        self.assetCount = snapshot.holdings.count
        self.weightPercent = totalPortfolioValue > 0 ? (snapshot.totalAsset / totalPortfolioValue) * 100 : 0
        self.holdings = snapshot.holdings
            .sorted { $0.evaluationAmount > $1.evaluationAmount }
            .map {
                PortfolioHoldingRowState(
                    holding: $0,
                    exchange: snapshot.exchange,
                    totalPortfolioValue: totalPortfolioValue
                )
            }
        self.partialFailureMessage = snapshot.partialFailureMessage
    }
}

struct PortfolioTopAssetViewState: Identifiable, Equatable {
    var id: String { symbol }

    let symbol: String
    let name: String
    let totalQuantity: Double
    let evaluationAmount: Double
    let profitLoss: Double
    let weightPercent: Double
    let exchangeCount: Int
}

struct PortfolioOverviewViewState: Equatable {
    let summary: PortfolioOverviewCardState
    let exchangeSections: [ExchangePortfolioSectionViewState]
    let exchangeDistribution: [PortfolioAllocationRowState]
    let assetDistribution: [PortfolioAllocationRowState]
    let topAssets: [PortfolioTopAssetViewState]
    let coinWeightPercent: Double
    let cashWeightPercent: Double
    let warningMessage: String?

    init(
        snapshots: [PortfolioSnapshot],
        connectedAssetExchanges: [Exchange],
        warningMessage: String? = nil,
        topAssetLimit: Int = 6
    ) {
        let orderedSnapshots = Self.orderedSnapshots(snapshots)
        let totalAsset = orderedSnapshots.reduce(0) { $0 + $1.totalAsset }
        let availableAsset = orderedSnapshots.reduce(0) { $0 + $1.availableAsset }
        let lockedAsset = orderedSnapshots.reduce(0) { $0 + $1.lockedAsset }
        let cash = orderedSnapshots.reduce(0) { $0 + $1.cash }
        let totalPnl = orderedSnapshots.reduce(0) { partialResult, snapshot in
            partialResult + snapshot.holdings.reduce(0) { $0 + $1.profitLoss }
        }
        let investedAmount = totalAsset - totalPnl
        let totalPnlPercent = investedAmount > 0 ? (totalPnl / investedAmount) * 100 : 0
        let nonEmptySnapshots = orderedSnapshots.filter {
            $0.totalAsset > 0 || $0.cash > 0 || !$0.holdings.isEmpty
        }
        let activeExchangeCount = max(
            Set(nonEmptySnapshots.map(\.exchange)).count,
            connectedAssetExchanges.count
        )

        self.summary = PortfolioOverviewCardState(
            totalAsset: totalAsset,
            availableAsset: availableAsset,
            lockedAsset: lockedAsset,
            cash: cash,
            totalPnl: totalPnl,
            totalPnlPercent: totalPnlPercent,
            exchangeCount: activeExchangeCount
        )
        self.exchangeSections = nonEmptySnapshots.map {
            ExchangePortfolioSectionViewState(snapshot: $0, totalPortfolioValue: totalAsset)
        }
        self.exchangeDistribution = Self.makeExchangeDistribution(
            sections: exchangeSections,
            totalAsset: totalAsset
        )
        self.topAssets = Self.makeTopAssets(
            snapshots: orderedSnapshots,
            totalAsset: totalAsset,
            limit: topAssetLimit
        )
        self.assetDistribution = Self.makeAssetDistribution(topAssets: topAssets)
        self.cashWeightPercent = totalAsset > 0 ? (cash / totalAsset) * 100 : 0
        self.coinWeightPercent = max(0, 100 - cashWeightPercent)
        self.warningMessage = warningMessage
    }

    private static func orderedSnapshots(_ snapshots: [PortfolioSnapshot]) -> [PortfolioSnapshot] {
        let order = Dictionary(uniqueKeysWithValues: Exchange.allCases.enumerated().map { ($0.element, $0.offset) })
        return snapshots.sorted {
            let leftOrder = order[$0.exchange] ?? Int.max
            let rightOrder = order[$1.exchange] ?? Int.max
            if leftOrder == rightOrder {
                return $0.exchange.rawValue < $1.exchange.rawValue
            }
            return leftOrder < rightOrder
        }
    }

    private static func makeExchangeDistribution(
        sections: [ExchangePortfolioSectionViewState],
        totalAsset: Double
    ) -> [PortfolioAllocationRowState] {
        sections
            .filter { $0.totalAsset > 0 }
            .map {
                PortfolioAllocationRowState(
                    id: "exchange-\($0.exchange.rawValue)",
                    title: $0.exchange.displayName,
                    subtitle: "\($0.assetCount)개 자산",
                    amount: $0.totalAsset,
                    percent: totalAsset > 0 ? ($0.totalAsset / totalAsset) * 100 : 0,
                    tintHex: Self.tintHex(for: $0.exchange)
                )
            }
    }

    private static func makeTopAssets(
        snapshots: [PortfolioSnapshot],
        totalAsset: Double,
        limit: Int
    ) -> [PortfolioTopAssetViewState] {
        let grouped = Dictionary(grouping: snapshots.flatMap { snapshot in
            snapshot.holdings.map { (snapshot.exchange, $0) }
        }, by: { $0.1.symbol })

        return grouped.map { symbol, entries in
            let quantity = entries.reduce(0) { $0 + $1.1.totalQuantity }
            let evaluationAmount = entries.reduce(0) { $0 + $1.1.evaluationAmount }
            let profitLoss = entries.reduce(0) { $0 + $1.1.profitLoss }
            let exchanges = Set(entries.map { $0.0 })
            return PortfolioTopAssetViewState(
                symbol: symbol,
                name: CoinCatalog.coin(symbol: symbol).name,
                totalQuantity: quantity,
                evaluationAmount: evaluationAmount,
                profitLoss: profitLoss,
                weightPercent: totalAsset > 0 ? (evaluationAmount / totalAsset) * 100 : 0,
                exchangeCount: exchanges.count
            )
        }
        .sorted { $0.evaluationAmount > $1.evaluationAmount }
        .prefix(limit)
        .map { $0 }
    }

    private static func makeAssetDistribution(
        topAssets: [PortfolioTopAssetViewState]
    ) -> [PortfolioAllocationRowState] {
        topAssets.map {
            PortfolioAllocationRowState(
                id: "asset-\($0.symbol)",
                title: $0.symbol,
                subtitle: $0.name,
                amount: $0.evaluationAmount,
                percent: $0.weightPercent,
                tintHex: Self.tintHex(forSymbol: $0.symbol)
            )
        }
    }

    private static func tintHex(for exchange: Exchange) -> String {
        switch exchange {
        case .upbit:
            return "#0050FF"
        case .bithumb:
            return "#F89F1B"
        case .coinone:
            return "#00C4B3"
        case .korbit:
            return "#4A90D9"
        case .binance:
            return "#F0B90B"
        }
    }

    private static func tintHex(forSymbol symbol: String) -> String {
        let palette = ["#F59E0B", "#EF4444", "#3B82F6", "#10B981", "#8B5CF6", "#22D3EE"]
        let index = abs(symbol.hashValue % palette.count)
        return palette[index]
    }
}

enum PortfolioHistoryEventSource: String, Equatable {
    case tradeFill = "trade_fill"
    case deposit = "deposit"
    case withdrawal = "withdrawal"
    case transfer = "transfer"
    case realizedBalanceChange = "realized_balance_change"
    case unknown = "unknown"
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
    let eventSource: PortfolioHistoryEventSource
    let rawSourceLabel: String?
    let isVerifiedUserEvent: Bool
    let isMockLike: Bool
    let hasUserScope: Bool
    let relatedEventIdentifier: String?
}
