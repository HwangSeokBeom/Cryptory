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

    private static let controlTypes: Set<String> = ["welcome", "subscribed", "pong", "ping", "ack", "error"]

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

    /// Builds the server's bounded public-market subscription contract.
    static func subscriptionMessage(for subscription: PublicMarketSubscription, action: String) -> String {
        var payload: [String: Any] = [
            "action": action,
            "channel": subscription.channel == .ticker ? "tickers" : subscription.channel.rawValue
        ]

        if subscription.channel == .candles {
            payload["type"] = action
            payload["channel"] = "market.candle"
            payload["exchange"] = subscription.exchange
            payload["symbol"] = subscription.symbol
            payload["quoteCurrency"] = subscription.quoteCurrency?.rawValue
            payload["timeframe"] = subscription.interval?.uppercased()
        } else if subscription.channel == .ticker {
            payload["exchanges"] = subscription.exchange.map { [$0] }
            payload["symbols"] = subscription.symbol.map { [$0] }
        } else {
            payload["exchange"] = subscription.exchange
            payload["symbols"] = subscription.symbol.map { [$0] }
        }

        let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
