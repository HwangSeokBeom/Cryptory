import Foundation

enum FlashType {
    case up, down
}

struct TickerData {
    var price: Double
    var change: Double
    var volume: Double
    var high24: Double
    var low24: Double
    var sparkline: [Double]
    var flash: FlashType?
}
