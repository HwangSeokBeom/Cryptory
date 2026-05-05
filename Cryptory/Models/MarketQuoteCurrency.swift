import Foundation

enum MarketQuoteCurrency: String, CaseIterable, Identifiable, Codable {
    case krw = "KRW"
    case btc = "BTC"
    case usdt = "USDT"
    case eth = "ETH"

    var id: String { rawValue }

    var title: String { rawValue }

    var apiValue: String { rawValue }

    var marketDisplayName: String {
        switch self {
        case .krw:
            return "원화"
        case .btc:
            return "BTC"
        case .usdt:
            return "USDT"
        case .eth:
            return "ETH"
        }
    }
}

enum MarketRealtimeStatus: Equatable {
    case disconnected
    case connecting
    case connected
    case reconnecting
    case failed
}

enum ChartViewState: Equatable {
    case idle
    case loadingInitial
    case loaded([CandleData], MarketRealtimeStatus)
    case refreshing([CandleData])
    case failed(String)
}
