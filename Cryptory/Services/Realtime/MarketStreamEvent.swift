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
    var coalescingKey: String? {
        switch self {
        case .connectionState, .trades:
            return nil
        case .ticker(let payload):
            return "ticker|\(payload.exchange)|\(payload.symbol)"
        case .orderbook(let payload):
            return "orderbook|\(payload.exchange)|\(payload.symbol)"
        case .candles(let payload):
            return "candles|\(payload.exchange)|\(payload.symbol)|\(payload.interval)"
        }
    }

    /// Key used to bound pending trade batches per market.
    var tradeBufferKey: String? {
        if case .trades(let payload) = self {
            return "trades|\(payload.exchange)|\(payload.symbol)"
        }
        return nil
    }
}

// The stream payload structs are value types whose members are all Sendable,
// so they satisfy Sendable implicitly (internal types, same module). No
// explicit or @unchecked conformances are required here.
