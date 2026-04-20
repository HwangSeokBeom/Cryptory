import XCTest
@testable import Cryptory

final class WebSocketParserTests: XCTestCase {

    func testMarketWebSocketTickerParserMatchesContract() {
        let message = """
        {
          "type": "ticker",
          "exchange": "upbit",
          "symbol": "BTC",
          "data": {
            "price": 125000000,
            "changePercent": 1.25,
            "volume24h": 123456789,
            "high24": 126000000,
            "low24": 120000000
          }
        }
        """

        guard case .some(.ticker(let payload)) = MarketWebSocketMessageParser.parse(message) else {
            return XCTFail("Expected ticker payload")
        }

        XCTAssertEqual(payload.exchange, "upbit")
        XCTAssertEqual(payload.symbol, "BTC")
        XCTAssertEqual(payload.ticker.price, 125000000)
        XCTAssertEqual(payload.ticker.change, 1.25)
        XCTAssertEqual(payload.ticker.volume, 123456789)
        XCTAssertEqual(payload.ticker.high24, 126000000)
        XCTAssertEqual(payload.ticker.low24, 120000000)
    }

    func testMarketWebSocketOrderbookParserMatchesContract() {
        let message = """
        {
          "type": "orderbook",
          "exchange": "bithumb",
          "symbol": "ETH",
          "data": {
            "asks": [
              { "price": 4500000, "quantity": 0.52 }
            ],
            "bids": [
              { "price": 4499000, "quantity": 0.71 }
            ]
          }
        }
        """

        guard case .some(.orderbook(let payload)) = MarketWebSocketMessageParser.parse(message) else {
            return XCTFail("Expected orderbook payload")
        }

        XCTAssertEqual(payload.exchange, "bithumb")
        XCTAssertEqual(payload.symbol, "ETH")
        XCTAssertEqual(payload.orderbook.asks.first?.price, 4500000)
        XCTAssertEqual(payload.orderbook.asks.first?.qty, 0.52)
        XCTAssertEqual(payload.orderbook.bids.first?.price, 4499000)
        XCTAssertEqual(payload.orderbook.bids.first?.qty, 0.71)
    }

    func testMarketWebSocketTradesParserMatchesContract() {
        let message = """
        {
          "type": "trades",
          "exchange": "coinone",
          "symbol": "XRP",
          "data": {
            "trades": [
              {
                "id": "trade-1",
                "price": 820,
                "quantity": 1200,
                "side": "buy",
                "executedAt": 1713182400000
              }
            ]
          }
        }
        """

        guard case .some(.trades(let payload)) = MarketWebSocketMessageParser.parse(message) else {
            return XCTFail("Expected trades payload")
        }

        XCTAssertEqual(payload.exchange, "coinone")
        XCTAssertEqual(payload.symbol, "XRP")
        XCTAssertEqual(payload.trades.first?.id, "trade-1")
        XCTAssertEqual(payload.trades.first?.price, 820)
        XCTAssertEqual(payload.trades.first?.quantity, 1200)
        XCTAssertEqual(payload.trades.first?.side, "buy")
    }

    func testMarketWebSocketTradesParserPreservesClockTextTimeField() {
        let message = """
        {
          "type": "trades",
          "exchange": "upbit",
          "symbol": "BTC",
          "data": {
            "trades": [
              {
                "id": "trade-2",
                "price": 125000000,
                "quantity": 0.01,
                "side": "sell",
                "time": "14:03:09"
              }
            ]
          }
        }
        """

        guard case .some(.trades(let payload)) = MarketWebSocketMessageParser.parse(message) else {
            return XCTFail("Expected trades payload")
        }

        XCTAssertEqual(payload.trades.first?.id, "trade-2")
        XCTAssertEqual(payload.trades.first?.executedAt, "14:03:09")
        XCTAssertNotEqual(payload.trades.first?.executedAt, "09:00:00")
    }

    func testMarketWebSocketCandleParserMatchesContract() {
        let message = """
        {
          "channel": "candles",
          "exchange": "upbit",
          "symbol": "BTC",
          "data": {
            "interval": "1h",
            "candles": [
              { "timestamp": 1713182400000, "open": 1, "high": 2, "low": 0.5, "close": 1.5, "volume": 10 }
            ]
          }
        }
        """

        guard case .some(.candles(let payload)) = MarketWebSocketMessageParser.parse(message) else {
            return XCTFail("Expected candle payload")
        }

        XCTAssertEqual(payload.interval, "1h")
        XCTAssertEqual(payload.candles.first?.close, 1.5)
    }

    func testPrivateWebSocketOrderParserMatchesContract() {
        let message = """
        {
          "channel": "orders",
          "exchange": "upbit",
          "data": {
            "id": "order-1",
            "exchange": "upbit",
            "symbol": "BTC",
            "side": "buy",
            "type": "limit",
            "price": 125000000,
            "quantity": 0.01,
            "remainingQuantity": 0.01,
            "status": "wait",
            "timestamp": 1713182400000
          }
        }
        """

        guard case .some(.order(let payload)) = PrivateWebSocketMessageParser.parse(message) else {
            return XCTFail("Expected private order payload")
        }

        XCTAssertEqual(payload.exchange, .upbit)
        XCTAssertEqual(payload.order.id, "order-1")
        XCTAssertEqual(payload.order.orderType, .limit)
    }
}
