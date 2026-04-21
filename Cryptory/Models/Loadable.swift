import Foundation

enum Loadable<Value> {
    case idle
    case loading
    case loaded(Value)
    case empty
    case failed(String)
}

extension Loadable {
    var value: Value? {
        guard case .loaded(let value) = self else { return nil }
        return value
    }

    var isLoading: Bool {
        if case .loading = self {
            return true
        }
        return false
    }

    var errorMessage: String? {
        guard case .failed(let message) = self else { return nil }
        return message
    }
}

enum ChartSectionState<Value> {
    case idle
    case loading
    case loaded(Value)
    case empty
    case unavailable(String)
    case failed(String)
}

extension ChartSectionState {
    var value: Value? {
        guard case .loaded(let value) = self else { return nil }
        return value
    }

    var hasResolvedResult: Bool {
        switch self {
        case .idle, .loading:
            return false
        case .loaded, .empty, .unavailable, .failed:
            return true
        }
    }
}

enum CandleState: Equatable {
    case idle
    case loading
    case loaded([CandleData])
    case empty
    case unavailable(String)
    case failed(String)
    case staleCache([CandleData])
    case refreshing([CandleData])
}

extension CandleState {
    var value: [CandleData]? {
        switch self {
        case .loaded(let candles), .staleCache(let candles), .refreshing(let candles):
            return candles
        case .idle, .loading, .empty, .unavailable, .failed:
            return nil
        }
    }

    var hasResolvedResult: Bool {
        switch self {
        case .idle, .loading:
            return false
        case .loaded, .empty, .unavailable, .failed, .staleCache, .refreshing:
            return true
        }
    }

    var sectionState: ChartSectionState<[CandleData]> {
        switch self {
        case .idle:
            return .idle
        case .loading, .refreshing:
            return .loading
        case .loaded(let candles), .staleCache(let candles):
            return .loaded(candles)
        case .empty:
            return .empty
        case .unavailable(let message):
            return .unavailable(message)
        case .failed(let message):
            return .failed(message)
        }
    }

    var warningMessage: String? {
        guard case .staleCache = self else { return nil }
        return "최신 차트 데이터를 불러오지 못했어요. 마지막 데이터를 표시 중입니다."
    }
}

enum OrderBookState: Equatable {
    case idle
    case loading
    case loaded(OrderbookData)
    case empty
    case unavailable(String)
    case failed(String)
    case staleCache(OrderbookData, String)
    case refreshing(OrderbookData)
}

extension OrderBookState {
    var value: OrderbookData? {
        switch self {
        case .loaded(let orderbook), .staleCache(let orderbook, _), .refreshing(let orderbook):
            return orderbook
        case .idle, .loading, .empty, .unavailable, .failed:
            return nil
        }
    }

    var hasResolvedResult: Bool {
        switch self {
        case .idle, .loading:
            return false
        case .loaded, .empty, .unavailable, .failed, .staleCache, .refreshing:
            return true
        }
    }

    var sectionState: ChartSectionState<OrderbookData> {
        switch self {
        case .idle:
            return .idle
        case .loading, .refreshing:
            return .loading
        case .loaded(let orderbook), .staleCache(let orderbook, _):
            return .loaded(orderbook)
        case .empty:
            return .empty
        case .unavailable(let message):
            return .unavailable(message)
        case .failed(let message):
            return .failed(message)
        }
    }

    var warningMessage: String? {
        guard case .staleCache(_, let message) = self else { return nil }
        return message
    }
}

enum TradesState: Equatable {
    case idle
    case loading
    case loaded([PublicTrade])
    case empty
    case unavailable(String)
    case failed(String)
    case staleCache([PublicTrade], String)
    case refreshing([PublicTrade])
}

extension TradesState {
    var value: [PublicTrade]? {
        switch self {
        case .loaded(let trades), .staleCache(let trades, _), .refreshing(let trades):
            return trades
        case .idle, .loading, .empty, .unavailable, .failed:
            return nil
        }
    }

    var hasResolvedResult: Bool {
        switch self {
        case .idle, .loading:
            return false
        case .loaded, .empty, .unavailable, .failed, .staleCache, .refreshing:
            return true
        }
    }

    var sectionState: ChartSectionState<[PublicTrade]> {
        switch self {
        case .idle:
            return .idle
        case .loading, .refreshing:
            return .loading
        case .loaded(let trades), .staleCache(let trades, _):
            return .loaded(trades)
        case .empty:
            return .empty
        case .unavailable(let message):
            return .unavailable(message)
        case .failed(let message):
            return .failed(message)
        }
    }

    var warningMessage: String? {
        guard case .staleCache(_, let message) = self else { return nil }
        return message
    }
}
