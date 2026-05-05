import Foundation

enum FlashType: String, Equatable, Codable {
    case up
    case down
}

enum TickerDelivery: String, Equatable, Codable {
    case snapshot
    case live
}

struct SparklinePoint: Codable, Equatable {
    var price: Double
    var timestamp: Date?
}

struct TickerData: Codable {
    var price: Double
    var change: Double
    var volume: Double
    var high24: Double
    var low24: Double
    var sparkline: [Double] = []
    var sparklinePoints: [SparklinePoint] = []
    var sparklinePointCount: Int? = nil
    var hasServerSparkline: Bool = false
    var sparklineSource: String? = nil
    var sparklineQuality: String? = nil
    var graphDisplayAllowed: Bool? = nil
    var sparklineUnavailableReason: String? = nil
    var previousPrice24h: Double? = nil
    var flash: FlashType? = nil
    var timestamp: Date? = nil
    var isStale: Bool = false
    var sourceExchange: Exchange? = nil
    var delivery: TickerDelivery = .snapshot
}
