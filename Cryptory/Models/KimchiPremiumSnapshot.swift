import Foundation

struct KimchiPremiumSnapshot: Equatable {
    let referenceExchange: Exchange
    let rows: [KimchiPremiumRow]
    let fetchedAt: Date?
    let isStale: Bool
    let warningMessage: String?
}

struct KimchiPremiumRow: Identifiable, Equatable {
    let id: String
    let symbol: String
    let exchange: Exchange
    let sourceExchange: Exchange
    let domesticPrice: Double?
    let referenceExchangePrice: Double?
    let premiumPercent: Double?
    let krwConvertedReference: Double?
    let usdKrwRate: Double?
    let timestamp: Date?
    let sourceExchangeTimestamp: Date?
    let referenceTimestamp: Date?
    let isStale: Bool
    let staleReason: String?
}
