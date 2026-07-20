import Foundation

/// Wraps the existing `MarketWebSocketMessageParser` wire contract, adding an
/// explicit distinction between protocol control frames and decode failures so
/// the engine's metrics can tell them apart.
enum MarketStreamDecoder {
    enum Result {
        case event(MarketWebSocketParsedMessage)
        /// Recognized protocol frame with no market payload
        /// (`subscribed` / `ping` / `pong` / `ack`).
        case control
        /// Unparseable or incomplete message. Never terminates the stream.
        case failure
    }

    private static let controlTypes: Set<String> = ["subscribed", "pong", "ping", "ack"]

    static func decode(_ text: String) -> Result {
        if let parsed = MarketWebSocketMessageParser.parse(text) {
            return .event(parsed)
        }
        // The parser returns nil for both control frames and malformed
        // payloads; re-inspect the envelope to classify.
        guard
            let data = text.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return .failure
        }
        let type = (json["type"] as? String ?? json["channel"] as? String)?.lowercased()
        if let type, controlTypes.contains(type) {
            return .control
        }
        return .failure
    }

    /// Builds the wire subscribe/unsubscribe message, byte-compatible with the
    /// legacy `WebSocketService.subscriptionMessage(for:action:)`.
    static func subscriptionMessage(for subscription: PublicMarketSubscription, action: String) -> String {
        var payload: [String: String] = [
            "type": action,
            "action": action,
            "channel": subscription.channel == .candles ? "market.candle" : subscription.channel.rawValue
        ]

        if let exchange = subscription.exchange {
            payload["exchange"] = exchange
        }
        if let symbol = subscription.symbol {
            payload["symbol"] = symbol
        }
        if let quoteCurrency = subscription.quoteCurrency {
            payload["quoteCurrency"] = quoteCurrency.rawValue
        }
        if let interval = subscription.interval {
            payload["timeframe"] = interval.uppercased()
        }

        let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
