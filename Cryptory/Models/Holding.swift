import Foundation

struct Holding: Identifiable, Equatable {
    var id: String { symbol }

    let symbol: String
    let totalQuantity: Double
    let availableQuantity: Double
    let lockedQuantity: Double
    let averageBuyPrice: Double
    let evaluationAmount: Double
    let profitLoss: Double
    let profitLossRate: Double

    var qty: Double { totalQuantity }
    var avgPrice: Double { averageBuyPrice }
}
