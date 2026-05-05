import Foundation

enum PriceAlertCondition: String, CaseIterable, Identifiable, Codable {
    case above
    case below

    var id: String { rawValue }

    var title: String {
        switch self {
        case .above: return "이상"
        case .below: return "이하"
        }
    }
}

enum PriceAlertRepeatPolicy: String, CaseIterable, Identifiable, Codable {
    case once
    case repeating

    var id: String { rawValue }

    var title: String {
        switch self {
        case .once: return "1회"
        case .repeating: return "반복"
        }
    }
}

struct PriceAlert: Identifiable, Equatable, Codable {
    let id: String
    let exchange: Exchange
    let symbol: String
    let quoteCurrency: MarketQuoteCurrency
    let condition: PriceAlertCondition
    let targetPrice: Double
    let repeatPolicy: PriceAlertRepeatPolicy
    let isActive: Bool
}

struct PriceAlertDraft: Equatable {
    var alertId: String?
    var exchange: Exchange
    var symbol: String
    var quoteCurrency: MarketQuoteCurrency
    var currentPrice: Double
    var condition: PriceAlertCondition
    var targetPriceText: String
    var repeatPolicy: PriceAlertRepeatPolicy
    var isActive: Bool
    var warningMessage: String?

    var targetPrice: Double? {
        Double(targetPriceText.replacingOccurrences(of: ",", with: ""))
    }

    static func make(
        existing alert: PriceAlert?,
        exchange: Exchange,
        symbol: String,
        quoteCurrency: MarketQuoteCurrency,
        currentPrice: Double
    ) -> PriceAlertDraft {
        PriceAlertDraft(
            alertId: alert?.id,
            exchange: exchange,
            symbol: symbol,
            quoteCurrency: quoteCurrency,
            currentPrice: currentPrice,
            condition: alert?.condition ?? .above,
            targetPriceText: alert.map { PriceFormatter.formatMarketPrice($0.targetPrice, quoteCurrency: quoteCurrency).replacingOccurrences(of: " BTC", with: "") } ?? "",
            repeatPolicy: alert?.repeatPolicy ?? .once,
            isActive: alert?.isActive ?? true,
            warningMessage: nil
        )
    }
}
