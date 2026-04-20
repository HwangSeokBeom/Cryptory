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

enum CandleState: Equatable {
    case idle
    case loading
    case loaded([CandleData])
    case empty
    case failed(String)
    case staleCache([CandleData])
    case refreshing([CandleData])
}

extension CandleState {
    var value: [CandleData]? {
        switch self {
        case .loaded(let candles), .staleCache(let candles), .refreshing(let candles):
            return candles
        case .idle, .loading, .empty, .failed:
            return nil
        }
    }

    var hasResolvedResult: Bool {
        switch self {
        case .idle, .loading:
            return false
        case .loaded, .empty, .failed, .staleCache, .refreshing:
            return true
        }
    }
}

enum OrderBookState: Equatable {
    case idle
    case loading
    case loaded(OrderbookData)
    case failed(String)
}

extension OrderBookState {
    var value: OrderbookData? {
        guard case .loaded(let orderbook) = self else { return nil }
        return orderbook
    }

    var hasResolvedResult: Bool {
        switch self {
        case .idle, .loading:
            return false
        case .loaded, .failed:
            return true
        }
    }
}

enum TradesState: Equatable {
    case idle
    case loading
    case loaded([PublicTrade])
    case failed(String)
}

extension TradesState {
    var value: [PublicTrade]? {
        guard case .loaded(let trades) = self else { return nil }
        return trades
    }

    var hasResolvedResult: Bool {
        switch self {
        case .idle, .loading:
            return false
        case .loaded, .failed:
            return true
        }
    }
}
