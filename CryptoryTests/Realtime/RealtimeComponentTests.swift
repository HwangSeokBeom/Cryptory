import XCTest
@testable import Cryptory

/// Deterministic unit tests for the realtime pipeline's value components:
/// reconnect policy, subscription registry, and the bounded event buffer.
final class RealtimeComponentTests: XCTestCase {
    // MARK: - ReconnectPolicy

    private let policy = ReconnectPolicy(
        initialDelay: .seconds(1),
        multiplier: 2,
        maxDelay: .seconds(30),
        jitterRatio: 0.2
    )

    func testExponentialBackoffIncreasesCorrectly() {
        XCTAssertEqual(policy.delay(forAttempt: 1, jitterUnit: 0.5), .seconds(1))
        XCTAssertEqual(policy.delay(forAttempt: 2, jitterUnit: 0.5), .seconds(2))
        XCTAssertEqual(policy.delay(forAttempt: 3, jitterUnit: 0.5), .seconds(4))
        XCTAssertEqual(policy.delay(forAttempt: 4, jitterUnit: 0.5), .seconds(8))
    }

    func testBackoffIsCapped() {
        XCTAssertEqual(policy.delay(forAttempt: 6, jitterUnit: 0.5), .seconds(30))
        XCTAssertEqual(policy.delay(forAttempt: 20, jitterUnit: 0.5), .seconds(30))
    }

    func testJitterRemainsInsideConfiguredRange() {
        for attempt in 1...8 {
            let base = policy.delay(forAttempt: attempt, jitterUnit: 0.5)
            let low = policy.delay(forAttempt: attempt, jitterUnit: 0)
            let high = policy.delay(forAttempt: attempt, jitterUnit: 0.999_999)
            XCTAssertEqual(low.asSeconds, base.asSeconds * 0.8, accuracy: 0.001)
            XCTAssertEqual(high.asSeconds, base.asSeconds * 1.2, accuracy: 0.001)
            for unit in [0.0, 0.1, 0.25, 0.75, 0.999] {
                let jittered = policy.delay(forAttempt: attempt, jitterUnit: unit).asSeconds
                XCTAssertGreaterThanOrEqual(jittered, base.asSeconds * 0.8 - 0.001)
                XCTAssertLessThanOrEqual(jittered, base.asSeconds * 1.2 + 0.001)
            }
        }
    }

    // MARK: - MarketSubscriptionRegistry

    private let tickerBTC = PublicMarketSubscription(channel: .ticker, exchange: "upbit", symbol: "BTC")
    private let tickerETH = PublicMarketSubscription(channel: .ticker, exchange: "upbit", symbol: "ETH")
    private let tradesBTC = PublicMarketSubscription(channel: .trades, exchange: "upbit", symbol: "BTC")

    func testTwoOwnersOfOneSubscriptionProduceOneUpstreamSubscribe() {
        var registry = MarketSubscriptionRegistry()
        let first = registry.replace(owner: UUID(), with: [tickerBTC])
        XCTAssertEqual(first.subscribe, [tickerBTC])

        let second = registry.replace(owner: UUID(), with: [tickerBTC])
        XCTAssertTrue(second.subscribe.isEmpty, "second owner must not re-subscribe upstream")
        XCTAssertTrue(second.unsubscribe.isEmpty)
        XCTAssertEqual(registry.subscriptionCount, 1)
        XCTAssertEqual(registry.totalOwnershipCount, 2)
    }

    func testRemovingOneOwnerDoesNotUnsubscribePrematurely() {
        var registry = MarketSubscriptionRegistry()
        let ownerA = UUID()
        let ownerB = UUID()
        _ = registry.replace(owner: ownerA, with: [tickerBTC])
        _ = registry.replace(owner: ownerB, with: [tickerBTC])

        let diff = registry.replace(owner: ownerB, with: [])
        XCTAssertTrue(diff.unsubscribe.isEmpty, "subscription still owned by ownerA")
        XCTAssertEqual(registry.activeSubscriptions, [tickerBTC])
    }

    func testRemovingFinalOwnerSendsOneUnsubscribe() {
        var registry = MarketSubscriptionRegistry()
        let ownerA = UUID()
        let ownerB = UUID()
        _ = registry.replace(owner: ownerA, with: [tickerBTC])
        _ = registry.replace(owner: ownerB, with: [tickerBTC])
        _ = registry.replace(owner: ownerB, with: [])

        let final = registry.replace(owner: ownerA, with: [])
        XCTAssertEqual(final.unsubscribe, [tickerBTC])
        XCTAssertTrue(registry.isEmpty)
    }

    func testRapidReplacementConvergesToFinalSet() {
        var registry = MarketSubscriptionRegistry()
        let owner = UUID()
        var subscribes: Set<PublicMarketSubscription> = []
        var unsubscribes: Set<PublicMarketSubscription> = []
        for target in [[tickerBTC], [tickerETH], [tickerBTC, tradesBTC], [tradesBTC]] {
            let diff = registry.replace(owner: owner, with: Set(target))
            subscribes.formUnion(diff.subscribe)
            unsubscribes.formUnion(diff.unsubscribe)
        }
        XCTAssertEqual(registry.activeSubscriptions, [tradesBTC])
        // Net effect converges: everything subscribed along the way except
        // the final target was also unsubscribed.
        XCTAssertEqual(subscribes.subtracting(unsubscribes), [tradesBTC])
    }

    func testRemoveOwnerReleasesOnlySoleOwnedSubscriptions() {
        var registry = MarketSubscriptionRegistry()
        let ownerA = UUID()
        let ownerB = UUID()
        _ = registry.replace(owner: ownerA, with: [tickerBTC, tickerETH])
        _ = registry.replace(owner: ownerB, with: [tickerBTC])

        let released = registry.removeOwner(ownerA)
        XCTAssertEqual(released, [tickerETH], "BTC ticker still owned by ownerB")
        XCTAssertEqual(registry.activeSubscriptions, [tickerBTC])
    }

    func testConflictingReplacementIsCanonicalAndIdempotent() {
        let krw = PublicMarketSubscription(
            channel: .ticker,
            marketIdentity: MarketIdentity(exchange: .upbit, symbol: "BTC", quoteCurrency: .krw)
        )
        let usdt = PublicMarketSubscription(
            channel: .ticker,
            marketIdentity: MarketIdentity(exchange: .upbit, symbol: "BTC", quoteCurrency: .usdt)
        )
        let owner = UUID()
        var registry = MarketSubscriptionRegistry()

        let first = registry.replace(owner: owner, with: [krw, usdt])
        let winner = try! XCTUnwrap(registry.activeSubscriptions.first)
        XCTAssertEqual(registry.activeSubscriptions.count, 1)
        XCTAssertEqual(first.subscribe, [winner])
        XCTAssertTrue(first.unsubscribe.isEmpty)

        for _ in 0..<5 {
            let repeated = registry.replace(owner: owner, with: [krw, usdt])
            XCTAssertTrue(repeated.isEmpty, "an identical malformed replacement must emit no wire mutation")
            XCTAssertEqual(registry.activeSubscriptions, [winner])
        }
    }

    func testConflictingReplacementWinnerIsIndependentOfRegistryAndInputConstructionOrder() {
        let krw = PublicMarketSubscription(
            channel: .ticker,
            marketIdentity: MarketIdentity(exchange: .upbit, symbol: "BTC", quoteCurrency: .krw)
        )
        let usdt = PublicMarketSubscription(
            channel: .ticker,
            marketIdentity: MarketIdentity(exchange: .upbit, symbol: "BTC", quoteCurrency: .usdt)
        )
        var forward = Set<PublicMarketSubscription>()
        forward.insert(krw)
        forward.insert(usdt)
        var reverse = Set<PublicMarketSubscription>()
        reverse.insert(usdt)
        reverse.insert(krw)

        var winners: Set<PublicMarketSubscription> = []
        for requested in [forward, reverse, forward, reverse] {
            var registry = MarketSubscriptionRegistry()
            _ = registry.replace(owner: UUID(), with: requested)
            winners.formUnion(registry.activeSubscriptions)
        }
        XCTAssertEqual(winners.count, 1, "fresh registries and reversed construction order must choose one winner")
    }

    func testRemovingCanonicalWinnerConvergesAndSingleQuoteReplacementIsUnchanged() {
        let krw = PublicMarketSubscription(
            channel: .ticker,
            marketIdentity: MarketIdentity(exchange: .upbit, symbol: "BTC", quoteCurrency: .krw)
        )
        let usdt = PublicMarketSubscription(
            channel: .ticker,
            marketIdentity: MarketIdentity(exchange: .upbit, symbol: "BTC", quoteCurrency: .usdt)
        )
        let owner = UUID()
        var registry = MarketSubscriptionRegistry()
        _ = registry.replace(owner: owner, with: [krw, usdt])
        let winner = try! XCTUnwrap(registry.activeSubscriptions.first)
        let loser = winner == krw ? usdt : krw

        let converged = registry.replace(owner: owner, with: [loser])
        XCTAssertEqual(converged.unsubscribe, [winner])
        XCTAssertEqual(converged.subscribe, [loser])
        XCTAssertEqual(registry.activeSubscriptions, [loser])

        let unchanged = registry.replace(owner: owner, with: [loser])
        XCTAssertTrue(unchanged.isEmpty, "ordinary single-quote replacement remains idempotent")
        XCTAssertEqual(registry.totalOwnershipCount, 1)
    }

    func testCanonicalConflictPreservesReferenceCountsForOtherOwners() {
        let krw = PublicMarketSubscription(
            channel: .ticker,
            marketIdentity: MarketIdentity(exchange: .upbit, symbol: "BTC", quoteCurrency: .krw)
        )
        let usdt = PublicMarketSubscription(
            channel: .ticker,
            marketIdentity: MarketIdentity(exchange: .upbit, symbol: "BTC", quoteCurrency: .usdt)
        )
        let eth = PublicMarketSubscription(
            channel: .ticker,
            marketIdentity: MarketIdentity(exchange: .upbit, symbol: "ETH", quoteCurrency: .krw)
        )
        let ownerA = UUID()
        let ownerB = UUID()
        var registry = MarketSubscriptionRegistry()
        _ = registry.replace(owner: ownerA, with: [eth])
        _ = registry.replace(owner: ownerB, with: [eth, krw, usdt])

        XCTAssertEqual(registry.subscriptionCount, 2, "one BTC winner plus non-conflicting ETH")
        XCTAssertEqual(registry.totalOwnershipCount, 3, "ETH retains both owners while BTC retains its owner")
        let repeated = registry.replace(owner: ownerB, with: [eth, krw, usdt])
        XCTAssertTrue(repeated.isEmpty)
        XCTAssertEqual(registry.totalOwnershipCount, 3)

        let released = registry.removeOwner(ownerB)
        XCTAssertEqual(released.count, 1, "only the sole-owned BTC winner unsubscribes")
        XCTAssertEqual(registry.activeSubscriptions, [eth])
        XCTAssertEqual(registry.totalOwnershipCount, 1)
    }

    // MARK: - MarketStreamEventBuffer

    private func ticker(_ price: Double, symbol: String = "BTC") -> MarketStreamEvent {
        .ticker(
            TickerStreamPayload(
                symbol: symbol,
                exchange: "upbit",
                ticker: TickerData(price: price, change: 0, volume: 0, high24: price, low24: price)
            )
        )
    }

    private func trades(_ id: String, symbol: String = "BTC") -> MarketStreamEvent {
        .trades(
            TradesStreamPayload(
                symbol: symbol,
                exchange: "upbit",
                trades: [PublicTrade(id: id, price: 1, quantity: 1, side: "buy", executedAt: "00:00:00", executedDate: nil)]
            )
        )
    }

    private func enqueue(
        _ event: MarketStreamEvent,
        into buffer: inout MarketStreamEventBuffer,
        capacity: Int = 1024,
        maxTradeBatches: Int = 64
    ) -> MarketStreamEventBuffer.EnqueueResult {
        buffer.enqueue(event, at: .zero, capacity: capacity, maxTradeBatchesPerMarket: maxTradeBatches)
    }

    func testTickerCoalescingKeepsNewestValue() {
        var buffer = MarketStreamEventBuffer()
        _ = enqueue(ticker(1), into: &buffer)
        let second = enqueue(ticker(2), into: &buffer)
        let third = enqueue(ticker(3), into: &buffer)
        XCTAssertTrue(second.coalescedTicker)
        XCTAssertTrue(third.coalescedTicker)
        XCTAssertEqual(buffer.count, 1)
        guard case .ticker(let payload)? = buffer.dequeue()?.event else {
            return XCTFail("expected a ticker")
        }
        XCTAssertEqual(payload.ticker.price, 3)
    }

    func testSeparateMarketTickersDoNotOverwriteEachOther() {
        var buffer = MarketStreamEventBuffer()
        _ = enqueue(ticker(1, symbol: "BTC"), into: &buffer)
        _ = enqueue(ticker(2, symbol: "ETH"), into: &buffer)
        _ = enqueue(ticker(3, symbol: "BTC"), into: &buffer)
        XCTAssertEqual(buffer.count, 2)
        guard case .ticker(let first)? = buffer.dequeue()?.event,
              case .ticker(let second)? = buffer.dequeue()?.event else {
            return XCTFail("expected two tickers")
        }
        XCTAssertEqual(first.symbol, "BTC")
        XCTAssertEqual(first.ticker.price, 3)
        XCTAssertEqual(second.symbol, "ETH")
        XCTAssertEqual(second.ticker.price, 2)
    }

    func testOrderbookReplacementFollowsDocumentedPolicy() {
        var buffer = MarketStreamEventBuffer()
        let older = OrderbookStreamPayload(
            symbol: "BTC",
            exchange: "upbit",
            orderbook: OrderbookData(asks: [OrderbookEntry(price: 100, qty: 1)], bids: [])
        )
        let newer = OrderbookStreamPayload(
            symbol: "BTC",
            exchange: "upbit",
            orderbook: OrderbookData(asks: [OrderbookEntry(price: 200, qty: 1)], bids: [])
        )
        _ = enqueue(.orderbook(older), into: &buffer)
        let result = enqueue(.orderbook(newer), into: &buffer)
        XCTAssertTrue(result.replacedOrderbook)
        XCTAssertFalse(result.coalescedTicker, "orderbook replacement is not counted as ticker coalescing")
        XCTAssertEqual(buffer.count, 1)
        guard case .orderbook(let payload)? = buffer.dequeue()?.event else {
            return XCTFail("expected an orderbook")
        }
        XCTAssertEqual(payload.orderbook.asks.first?.price, 200)
    }

    func testCandleUpdatesMergeByIntervalAndTimestamp() {
        var buffer = MarketStreamEventBuffer()
        let first = CandleStreamPayload(
            symbol: "BTC",
            exchange: "upbit",
            interval: "1h",
            candles: [
                CandleData(time: 1000, open: 1, high: 2, low: 0, close: 1, volume: 5),
                CandleData(time: 2000, open: 1, high: 2, low: 0, close: 2, volume: 5),
            ]
        )
        let update = CandleStreamPayload(
            symbol: "BTC",
            exchange: "upbit",
            interval: "1h",
            candles: [CandleData(time: 2000, open: 1, high: 3, low: 0, close: 3, volume: 9)]
        )
        _ = enqueue(.candles(first), into: &buffer)
        _ = enqueue(.candles(update), into: &buffer)
        XCTAssertEqual(buffer.count, 1)
        guard case .candles(let payload)? = buffer.dequeue()?.event else {
            return XCTFail("expected candles")
        }
        XCTAssertEqual(payload.candles.map(\.time), [1000, 2000])
        XCTAssertEqual(payload.candles.last?.close, 3, "newer candle data wins for the same timestamp")
    }

    func testCandleMergePreservesQuoteIdentity() {
        var buffer = MarketStreamEventBuffer()
        let first = CandleStreamPayload(
            symbol: "BTC",
            exchange: "upbit",
            interval: "1h",
            candles: [CandleData(time: 1000, open: 1, high: 2, low: 0, close: 1, volume: 5)],
            quoteCurrency: .krw
        )
        let update = CandleStreamPayload(
            symbol: "BTC",
            exchange: "upbit",
            interval: "1h",
            candles: [CandleData(time: 2000, open: 2, high: 3, low: 1, close: 2, volume: 6)],
            quoteCurrency: .krw
        )

        _ = enqueue(.candles(first), into: &buffer)
        let result = enqueue(.candles(update), into: &buffer)
        XCTAssertTrue(result.mergedCandle)
        guard case .candles(let payload)? = buffer.dequeue()?.event else {
            return XCTFail("expected a merged candle payload")
        }
        XCTAssertEqual(payload.quoteCurrency, .krw, "coalescing must never erase a known quote")
        XCTAssertEqual(payload.candles.map(\.time), [1000, 2000])
    }

    func testCandleDifferentQuotesStaySeparateAndQuoteLessMergeRemainsCompatible() {
        var buffer = MarketStreamEventBuffer()
        func payload(_ quote: MarketQuoteCurrency?, time: Int) -> CandleStreamPayload {
            CandleStreamPayload(
                symbol: "BTC",
                exchange: "upbit",
                interval: "1h",
                candles: [CandleData(time: time, open: 1, high: 2, low: 0, close: 1, volume: 5)],
                quoteCurrency: quote
            )
        }

        _ = enqueue(.candles(payload(.krw, time: 1000)), into: &buffer)
        let conflicting = enqueue(.candles(payload(.usdt, time: 2000)), into: &buffer)
        XCTAssertFalse(conflicting.mergedCandle)
        XCTAssertEqual(buffer.count, 2, "complete identities with different quotes must never merge")

        var quoteLess = MarketStreamEventBuffer()
        _ = enqueue(.candles(payload(nil, time: 1000)), into: &quoteLess)
        let legacy = enqueue(.candles(payload(nil, time: 2000)), into: &quoteLess)
        XCTAssertTrue(legacy.mergedCandle, "quote-less gateway payloads retain their documented compatibility")
        guard case .candles(let merged)? = quoteLess.dequeue()?.event else {
            return XCTFail("expected quote-less merged candles")
        }
        XCTAssertNil(merged.quoteCurrency)
        XCTAssertEqual(merged.candles.map(\.time), [1000, 2000])
    }

    func testTradeBufferingRemainsBounded() {
        var buffer = MarketStreamEventBuffer()
        var dropped = 0
        for index in 0..<10 {
            let result = enqueue(trades("t\(index)"), into: &buffer, maxTradeBatches: 3)
            dropped += result.totalDropped
        }
        XCTAssertEqual(buffer.count, 3)
        XCTAssertEqual(dropped, 7)
        var remainingIDs: [String] = []
        while let queued = buffer.dequeue() {
            if case .trades(let payload) = queued.event {
                remainingIDs.append(contentsOf: payload.trades.map(\.id))
            }
        }
        XCTAssertEqual(remainingIDs, ["t7", "t8", "t9"], "oldest batches are dropped first")
    }

    func testTotalCapacityBoundDropsOldestNonStateEvent() {
        var buffer = MarketStreamEventBuffer()
        _ = enqueue(.connectionState(.idle), into: &buffer, capacity: 4)
        var dropped = 0
        for index in 0..<8 {
            let result = enqueue(trades("t\(index)"), into: &buffer, capacity: 4, maxTradeBatches: 64)
            dropped += result.totalDropped
        }
        XCTAssertEqual(buffer.count, 4)
        XCTAssertEqual(dropped, 5)
        guard case .connectionState? = buffer.dequeue()?.event else {
            return XCTFail("connection-state event must survive capacity pressure")
        }
    }

    func testBoundedBufferDoesNotGrowIndefinitely() {
        var buffer = MarketStreamEventBuffer()
        for index in 0..<10_000 {
            _ = enqueue(trades("t\(index)", symbol: "COIN\(index % 50)"), into: &buffer, capacity: 16, maxTradeBatches: 4)
        }
        XCTAssertLessThanOrEqual(buffer.count, 16)
    }

    // MARK: - Decoder classification

    func testMalformedMessagesClassifyAsFailures() {
        XCTAssertNotNil(asFailure("not json"))
        XCTAssertNotNil(asFailure("{\"type\":\"ticker\"}"))
        if case .control = MarketStreamDecoder.decode("{\"type\":\"pong\"}") {} else {
            XCTFail("pong must classify as control, not failure")
        }
        if case .event = MarketStreamDecoder.decode(RealtimeFixtureLoader.tickerMessage(price: 100)) {} else {
            XCTFail("valid ticker must decode")
        }
    }

    private func asFailure(_ text: String) -> String? {
        if case .failure = MarketStreamDecoder.decode(text) { return text }
        return nil
    }
}
