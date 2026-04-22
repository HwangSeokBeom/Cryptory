import Foundation

struct PublicTrade: Identifiable, Equatable {
    let id: String
    let price: Double
    let quantity: Double
    let side: String
    let executedAt: String
    let executedDate: Date?

    init(
        id: String,
        price: Double,
        quantity: Double,
        side: String,
        executedAt: String,
        executedDate: Date? = nil
    ) {
        self.id = id
        self.price = price
        self.quantity = quantity
        self.side = side
        self.executedAt = executedAt
        self.executedDate = executedDate
    }
}

struct ChartTradeRowViewState: Identifiable, Equatable {
    let stableRenderID: String
    let trade: PublicTrade

    nonisolated var id: String { stableRenderID }
    nonisolated var price: Double { trade.price }
    nonisolated var quantity: Double { trade.quantity }
    nonisolated var side: String { trade.side }
    nonisolated var executedAt: String { trade.executedAt }

    nonisolated init(
        trade: PublicTrade,
        marketIdentity: MarketIdentity,
        occurrence: Int
    ) {
        self.trade = trade
        self.stableRenderID = Self.baseRenderKey(
            trade: trade,
            marketIdentity: marketIdentity
        ) + "|occ:\(occurrence)"
    }

    nonisolated static func baseRenderKey(
        trade: PublicTrade,
        marketIdentity: MarketIdentity
    ) -> String {
        let rawTradeID = trade.id.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTradeID = rawTradeID.isEmpty ? "missing" : rawTradeID
        let executedAt = trade.executedAt.trimmingCharacters(in: .whitespacesAndNewlines)
        let timestampComponent: String
        if let executedDate = trade.executedDate {
            timestampComponent = String(
                Int((executedDate.timeIntervalSince1970 * 1_000).rounded())
            )
        } else if executedAt.isEmpty == false {
            timestampComponent = executedAt
        } else {
            timestampComponent = "na"
        }

        return [
            marketIdentity.cacheKey,
            "trade:\(normalizedTradeID)",
            "ts:\(timestampComponent)",
            "px:\(normalizedNumberComponent(trade.price))",
            "qty:\(normalizedNumberComponent(trade.quantity))",
            "side:\(trade.side.lowercased())"
        ].joined(separator: "|")
    }

    private nonisolated static func normalizedNumberComponent(_ value: Double) -> String {
        guard value.isFinite else {
            return "nan"
        }
        return String(format: "%.8f", value)
    }
}
