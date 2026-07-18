import Foundation

/// Deterministic, privacy-safe wire-message fixtures for replay tests.
///
/// All fixtures are generated from fixed parameters: no real user data, no
/// tokens, no recorded production traffic. Prices and timestamps are synthetic
/// and reproducible run-to-run, and generation scales to high volume
/// (100k+ messages) without bundled files.
enum RealtimeFixtureLoader {
    static let baseTimestampMillis = 1_700_000_000_000

    static func tickerMessage(
        exchange: String = "upbit",
        symbol: String = "BTC",
        price: Double,
        sequence: Int = 0
    ) -> String {
        """
        {"type":"ticker","exchange":"\(exchange)","symbol":"\(symbol)","data":{"price":\(price),"changePercent":1.5,"volume24h":1000,"high24":\(price + 10),"low24":\(price - 10),"timestamp":\(baseTimestampMillis + sequence)}}
        """
    }

    static func orderbookMessage(
        exchange: String = "upbit",
        symbol: String = "BTC",
        askPrice: Double,
        sequence: Int = 0
    ) -> String {
        """
        {"type":"orderbook","exchange":"\(exchange)","symbol":"\(symbol)","data":{"asks":[{"price":\(askPrice),"quantity":1.5}],"bids":[{"price":\(askPrice - 1),"quantity":2.0}],"timestamp":\(baseTimestampMillis + sequence)}}
        """
    }

    static func tradesMessage(
        exchange: String = "upbit",
        symbol: String = "BTC",
        price: Double,
        sequence: Int = 0
    ) -> String {
        """
        {"type":"trades","exchange":"\(exchange)","symbol":"\(symbol)","data":{"trades":[{"id":"t\(sequence)","price":\(price),"quantity":0.5,"side":"buy","timestamp":\(baseTimestampMillis + sequence)}]}}
        """
    }

    static func candleMessage(
        exchange: String = "upbit",
        symbol: String = "BTC",
        interval: String = "1h",
        close: Double,
        candleTimeMillis: Int,
        sequence: Int = 0
    ) -> String {
        """
        {"type":"candles","exchange":"\(exchange)","symbol":"\(symbol)","timeframe":"\(interval)","data":{"candles":[{"open":\(close - 1),"high":\(close + 1),"low":\(close - 2),"close":\(close),"volume":10,"timestamp":\(candleTimeMillis)}]}}
        """
    }

    // MARK: - Required fixture streams

    /// Normal ticker stream: strictly increasing prices for one market.
    static func normalTickerStream(count: Int, exchange: String = "upbit", symbol: String = "BTC") -> [String] {
        (0..<count).map { index in
            tickerMessage(exchange: exchange, symbol: symbol, price: 100.0 + Double(index), sequence: index)
        }
    }

    /// Duplicate ticker stream: every price repeated back-to-back.
    static func duplicateTickerStream(count: Int) -> [String] {
        (0..<count).flatMap { index -> [String] in
            let message = tickerMessage(price: 100.0 + Double(index), sequence: index)
            return [message, message]
        }
    }

    /// Out-of-order stream: timestamps and prices deliberately unsorted
    /// (deterministic shuffle by stride).
    static func outOfOrderTickerStream(count: Int) -> [String] {
        let evens = stride(from: 0, to: count, by: 2)
        let odds = stride(from: 1, to: count, by: 2)
        return (Array(evens.reversed()) + Array(odds)).map { index in
            tickerMessage(price: 100.0 + Double(index), sequence: index)
        }
    }

    /// Malformed payload stream: valid messages interleaved with malformed
    /// JSON, wrong shapes, and missing required fields.
    static func malformedPayloadStream() -> [String] {
        [
            tickerMessage(price: 101, sequence: 0),
            "not json at all",
            "{\"type\":\"ticker\"}",
            "{\"type\":\"ticker\",\"exchange\":\"upbit\",\"symbol\":\"BTC\",\"data\":{}}",
            "{\"unexpected\":true}",
            tickerMessage(price: 102, sequence: 5),
        ]
    }

    /// Reconnect stream: messages intended for delivery across a connection
    /// drop (first batch, then the post-reconnect batch).
    static func reconnectStream() -> (beforeDrop: [String], afterReconnect: [String]) {
        (
            beforeDrop: normalTickerStream(count: 5),
            afterReconnect: (5..<10).map { tickerMessage(price: 100.0 + Double($0), sequence: $0) }
        )
    }

    /// Multi-market high-volume stream: `count` messages round-robined over
    /// `markets` markets on two exchanges.
    static func multiMarketHighVolumeStream(count: Int, markets: Int = 20) -> [String] {
        let symbols = (0..<markets).map { "COIN\($0)" }
        let exchanges = ["upbit", "bithumb"]
        return (0..<count).map { index in
            tickerMessage(
                exchange: exchanges[index % exchanges.count],
                symbol: symbols[index % symbols.count],
                price: 100.0 + Double(index % 500),
                sequence: index
            )
        }
    }
}
