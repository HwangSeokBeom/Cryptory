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

    var apiValue: String {
        rawValue.uppercased()
    }

    init?(apiValue: String) {
        self.init(rawValue: apiValue.lowercased())
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

    var apiValue: String {
        switch self {
        case .once: return "ONCE"
        case .repeating: return "REPEAT"
        }
    }

    init?(apiValue: String) {
        switch apiValue.uppercased() {
        case "ONCE": self = .once
        case "REPEAT": self = .repeating
        default: return nil
        }
    }
}

enum PriceAlertSupport {
    static let message = "가격 알림은 현재 업비트·빗썸의 KRW/BTC 마켓에서만 지원해요."

    static func isSupported(exchange: Exchange, quoteCurrency: MarketQuoteCurrency) -> Bool {
        [.upbit, .bithumb].contains(exchange)
            && [.krw, .btc].contains(quoteCurrency)
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
