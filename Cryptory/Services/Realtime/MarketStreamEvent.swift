import Foundation

/// An event emitted by `MarketStreamEngine` to its consumers.
///
/// Reuses the existing stream payload types so the compatibility adapter can
/// forward them to `CryptoViewModel` unchanged.
enum MarketStreamEvent: Sendable {
    case connectionState(MarketStreamConnectionState)
    case ticker(TickerStreamPayload)
    case orderbook(OrderbookStreamPayload)
    case trades(TradesStreamPayload)
    case candles(CandleStreamPayload)

    /// Coalescing key: events with the same non-nil key may replace each
    /// other in a pending buffer according to the per-kind policy documented
    /// in Docs/REALTIME_PIPELINE.md. Connection-state events and trades never
    /// coalesce.
    ///
    /// The key carries the complete market identity — exchange, quote
    /// currency, and symbol — so two markets that share an exchange/symbol
    /// pair but differ in quote (e.g. BTC/KRW vs BTC/USDT) can never replace
    /// each other's pending events.
    var coalescingKey: String? {
        switch self {
        case .connectionState, .trades:
            return nil
        case .ticker(let payload):
            return "ticker|\(payload.exchange)|\(Self.quoteComponent(payload.quoteCurrency))|\(payload.symbol)"
        case .orderbook(let payload):
            return "orderbook|\(payload.exchange)|\(Self.quoteComponent(payload.quoteCurrency))|\(payload.symbol)"
        case .candles(let payload):
            return "candles|\(payload.exchange)|\(Self.quoteComponent(payload.quoteCurrency))|\(payload.symbol)|\(payload.interval)"
        }
    }

    /// Key used to bound pending trade batches per market (complete identity,
    /// same reasoning as `coalescingKey`).
    var tradeBufferKey: String? {
        if case .trades(let payload) = self {
            return "trades|\(payload.exchange)|\(Self.quoteComponent(payload.quoteCurrency))|\(payload.symbol)"
        }
        return nil
    }

    /// Quote-independent channel identity (channel, exchange, symbol, and
    /// interval for candles). The engine keys its live-identity registry on
    /// this value: at most one quote identity is live per channel key, and
    /// buffered events from a replaced identity are discarded by token
    /// validation (see `MarketStreamEngine`).
    var channelIdentityKey: String? {
        switch self {
        case .connectionState:
            return nil
        case .ticker(let payload):
            return "ticker|\(payload.exchange)|\(payload.symbol)|-"
        case .orderbook(let payload):
            return "orderbook|\(payload.exchange)|\(payload.symbol)|-"
        case .trades(let payload):
            return "trades|\(payload.exchange)|\(payload.symbol)|-"
        case .candles(let payload):
            return "candles|\(payload.exchange)|\(payload.symbol)|\(payload.interval)"
        }
    }

    /// The quote identity the event was decoded/stamped with, if any.
    var quoteCurrency: MarketQuoteCurrency? {
        switch self {
        case .connectionState:
            return nil
        case .ticker(let payload):
            return payload.quoteCurrency
        case .orderbook(let payload):
            return payload.quoteCurrency
        case .trades(let payload):
            return payload.quoteCurrency
        case .candles(let payload):
            return payload.quoteCurrency
        }
    }

    /// Stamps the resolved quote identity onto the payload (engine-only, at
    /// decode time from the live subscription registry).
    mutating func stampQuoteCurrency(_ quoteCurrency: MarketQuoteCurrency?) {
        switch self {
        case .connectionState:
            break
        case .ticker(var payload):
            payload.quoteCurrency = quoteCurrency
            self = .ticker(payload)
        case .orderbook(var payload):
            payload.quoteCurrency = quoteCurrency
            self = .orderbook(payload)
        case .trades(var payload):
            payload.quoteCurrency = quoteCurrency
            self = .trades(payload)
        case .candles(var payload):
            payload.quoteCurrency = quoteCurrency
            self = .candles(payload)
        }
    }

    private static func quoteComponent(_ quoteCurrency: MarketQuoteCurrency?) -> String {
        quoteCurrency?.rawValue ?? "-"
    }
}

// The stream payload structs are value types whose members are all Sendable,
// so they satisfy Sendable implicitly (internal types, same module). No
// explicit or @unchecked conformances are required here.
