import Foundation

struct OrderbookEntry: Identifiable, Equatable {
    let id = UUID()
    let price: Double
    let qty: Double

    static func == (lhs: OrderbookEntry, rhs: OrderbookEntry) -> Bool {
        lhs.price == rhs.price && lhs.qty == rhs.qty
    }
}

struct OrderbookData: Equatable {
    let asks: [OrderbookEntry]
    let bids: [OrderbookEntry]
    let timestamp: Date?
    let isStale: Bool

    init(asks: [OrderbookEntry], bids: [OrderbookEntry], timestamp: Date? = nil, isStale: Bool = false) {
        self.asks = asks
        self.bids = bids
        self.timestamp = timestamp
        self.isStale = isStale
    }
}
