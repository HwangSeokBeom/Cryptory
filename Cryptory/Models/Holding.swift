import Foundation

struct Holding: Identifiable {
    var id: String { symbol }
    var symbol: String
    var qty: Double
    var avgPrice: Double
}
