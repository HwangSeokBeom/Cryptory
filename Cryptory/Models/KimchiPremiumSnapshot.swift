import Foundation

enum KimchiPremiumFreshnessState: String, Equatable, Codable {
    case loading
    case partialUpdate
    case referencePriceDelayed
    case exchangeRateDelayed
    case stale
    case available
    case unavailable

    init(rawServerValue: String?) {
        let normalizedValue = rawServerValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")

        switch normalizedValue {
        case "loading", "pending", "updating":
            self = .loading
        case "partial", "partial_update", "partially_updated", "partial_failure":
            self = .partialUpdate
        case "reference_delayed", "reference_price_delayed", "global_delayed", "stale_reference":
            self = .referencePriceDelayed
        case "exchange_rate_delayed", "fx_delayed", "rate_delayed", "stale_fx":
            self = .exchangeRateDelayed
        case "stale", "old", "expired", "outdated":
            self = .stale
        case "fresh", "available", "ready", "live", "ok":
            self = .available
        case "unavailable", "missing", "none", "empty", "failed":
            self = .unavailable
        default:
            self = .available
        }
    }
}

struct KimchiPremiumSnapshot: Equatable {
    let referenceExchange: Exchange
    let rows: [KimchiPremiumRow]
    let fetchedAt: Date?
    let isStale: Bool
    let warningMessage: String?
    let partialFailureMessage: String?
    let failedSymbols: [String]
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
    let freshnessState: KimchiPremiumFreshnessState?
    let freshnessReason: String?
    let updatedAt: Date?

    init(
        id: String,
        symbol: String,
        exchange: Exchange,
        sourceExchange: Exchange,
        domesticPrice: Double?,
        referenceExchangePrice: Double?,
        premiumPercent: Double?,
        krwConvertedReference: Double?,
        usdKrwRate: Double?,
        timestamp: Date?,
        sourceExchangeTimestamp: Date?,
        referenceTimestamp: Date?,
        isStale: Bool,
        staleReason: String?,
        freshnessState: KimchiPremiumFreshnessState? = nil,
        freshnessReason: String? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.symbol = symbol
        self.exchange = exchange
        self.sourceExchange = sourceExchange
        self.domesticPrice = domesticPrice
        self.referenceExchangePrice = referenceExchangePrice
        self.premiumPercent = premiumPercent
        self.krwConvertedReference = krwConvertedReference
        self.usdKrwRate = usdKrwRate
        self.timestamp = timestamp
        self.sourceExchangeTimestamp = sourceExchangeTimestamp
        self.referenceTimestamp = referenceTimestamp
        self.isStale = isStale
        self.staleReason = staleReason
        self.freshnessState = freshnessState
        self.freshnessReason = freshnessReason
        self.updatedAt = updatedAt ?? timestamp ?? sourceExchangeTimestamp ?? referenceTimestamp
    }
}
