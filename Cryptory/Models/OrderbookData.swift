import Foundation

struct OrderbookEntry: Identifiable {
    let id = UUID()
    let price: Double
    let qty: Double
}

struct OrderbookData {
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
