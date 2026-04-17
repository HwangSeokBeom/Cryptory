import Foundation

struct TradingChance: Equatable {
    let exchange: Exchange
    let symbol: String
    let supportedOrderTypes: [OrderType]
    let minimumOrderAmount: Double?
    let maximumOrderAmount: Double?
    let priceUnit: Double?
    let quantityPrecision: Int?
    let bidBalance: Double
    let askBalance: Double
    let feeRate: Double?
    let warningMessage: String?
}

struct OrderRecord: Identifiable, Equatable {
    let id: String
    let symbol: String
    let side: String
    let orderType: OrderType
    let price: Double
    let averageExecutedPrice: Double?
    let qty: Double
    let executedQuantity: Double
    let remainingQuantity: Double
    let total: Double
    let time: String
    let createdAt: Date?
    let exchange: String
    let status: String
    let canCancel: Bool
}

struct TradeFill: Identifiable, Equatable {
    let id: String
    let orderID: String
    let symbol: String
    let side: String
    let price: Double
    let quantity: Double
    let fee: Double
    let executedAtText: String
    let executedAt: Date?
    let exchange: Exchange
}
