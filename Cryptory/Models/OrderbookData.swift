import Foundation

struct OrderbookEntry: Identifiable {
    let id = UUID()
    let price: Double
    let qty: Double
}

struct OrderbookData {
    let asks: [OrderbookEntry]
    let bids: [OrderbookEntry]
}
