import XCTest
@testable import Cryptory

/// Deterministic tests for the metrics semantics documented on
/// `RealtimeMetrics`: global ingress/emission counters stay independent of
/// consumer count, delivery counters aggregate per consumer, per-kind
/// replacement/merge/drop policies are represented distinctly, and only the
/// documented conservation equations hold.
final class RealtimeMetricsSemanticsTests: XCTestCase {
    private let tickerBTC = PublicMarketSubscription(channel: .ticker, exchange: "upbit", symbol: "BTC")
    private let orderbookBTC = PublicMarketSubscription(channel: .orderbook, exchange: "upbit", symbol: "BTC")
    private let tradesBTC = PublicMarketSubscription(channel: .trades, exchange: "upbit", symbol: "BTC")
    private let candlesBTC = PublicMarketSubscription(channel: .candles, exchange: "upbit", symbol: "BTC")

    private func makeEngine(
        maxTradeBatchesPerMarket: Int = 64
    ) -> (MarketStreamEngine, ScriptedWebSocketTransport, ManualTestClock) {
        let transport = ScriptedWebSocketTransport()
        let clock = ManualTestClock()
        let engine = MarketStreamEngine(
            url: URL(string: "wss://unit.test/ws/market")!,
            transport: transport,
            clock: clock,
            reconnectPolicy: ReconnectPolicy(
                initialDelay: .seconds(1),
                multiplier: 2,
                maxDelay: .seconds(30),
                jitterRatio: 0.2
            ),
            maxTradeBatchesPerMarket: maxTradeBatchesPerMarket,
            jitter: { 0.5 }
        )
        return (engine, transport, clock)
    }

    @discardableResult
    private func waitUntil(
        timeout: Duration = .seconds(30),
        _ condition: () async -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while !(await condition()) {
            if ContinuousClock.now >= deadline { return false }
            await Task.yield()
        }
        return true
    }

    private func assertDeliveryConservation(
        _ snapshot: RealtimeMetricsSnapshot,
        pendingBuffered: Int,
        _ note: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            snapshot.consumerEnqueues,
            snapshot.consumerDeliveries
                + snapshot.tickerEventsCoalesced
                + snapshot.orderbookSnapshotsReplaced
                + snapshot.candleUpdatesMergedOrReplaced
                + snapshot.tradeEventsDropped
                + snapshot.bufferEventsDropped
                + snapshot.staleIdentityEventsDropped
                + pendingBuffered,
            "delivery conservation must hold: \(note) — \(snapshot)",
            file: file,
            line: line
        )
    }

    func testTwoConsumersKeepGlobalAndDeliveryCountersSeparate() async {
        let (engine, transport, _) = makeEngine()
        let (firstID, _) = await engine.register()
        let (secondID, _) = await engine.register()
        await engine.replaceSubscriptions(owner: firstID, with: [tickerBTC])
        await engine.replaceSubscriptions(owner: secondID, with: [tickerBTC])
        let connection = try! XCTUnwrap(transport.lastConnection)
        connection.scriptOpened()
        for sequence in 0..<3 {
            connection.scriptText(RealtimeFixtureLoader.tickerMessage(price: 100 + Double(sequence), sequence: sequence))
        }
        await waitUntil { await engine.metricsSnapshot().messagesDecoded == 3 }

        var snapshot = await engine.metricsSnapshot()
        // Global ingress/emission counters are independent of consumer count.
        XCTAssertEqual(snapshot.messagesDecoded, 3, "decoded is global, not per consumer")
        // Logical events: connecting + connected + 3 tickers.
        XCTAssertEqual(snapshot.logicalEventsEmitted, 5)
        // Delivery counters fan out once per consumer.
        XCTAssertEqual(snapshot.consumerEnqueues, 10, "each logical event enqueues once per consumer")
        XCTAssertEqual(snapshot.tickerEventsCoalesced, 4, "2 of 3 tickers coalesce, per consumer")
        XCTAssertEqual(snapshot.consumerDeliveries, 0, "nothing pulled yet")
        // Per consumer buffer: connecting + connected + newest ticker.
        assertDeliveryConservation(snapshot, pendingBuffered: 6, "before unregister")

        await engine.unregister(firstID)
        await engine.unregister(secondID)
        snapshot = await engine.metricsSnapshot()
        XCTAssertEqual(snapshot.bufferEventsDropped, 6, "pending events become counted drops on unregister")
        assertDeliveryConservation(snapshot, pendingBuffered: 0, "after unregister")
        // The invalid comparison: with two consumers, decoded (3) can never
        // equal delivery-side counts (which scale by consumer count).
        XCTAssertNotEqual(snapshot.messagesDecoded, snapshot.consumerEnqueues)
    }

    func testOrderbookReplacementIsCountedDistinctly() async {
        let (engine, transport, _) = makeEngine()
        let (consumerID, _) = await engine.register()
        await engine.replaceSubscriptions(owner: consumerID, with: [orderbookBTC])
        let connection = try! XCTUnwrap(transport.lastConnection)
        connection.scriptOpened()
        connection.scriptText(RealtimeFixtureLoader.orderbookMessage(askPrice: 100, sequence: 0))
        connection.scriptText(RealtimeFixtureLoader.orderbookMessage(askPrice: 101, sequence: 1))
        await waitUntil { await engine.metricsSnapshot().messagesDecoded == 2 }

        let snapshot = await engine.metricsSnapshot()
        XCTAssertEqual(snapshot.orderbookSnapshotsReplaced, 1, "newer snapshot replaces the pending one")
        XCTAssertEqual(snapshot.tickerEventsCoalesced, 0, "replacement is not ticker coalescing")
        XCTAssertEqual(snapshot.candleUpdatesMergedOrReplaced, 0)
        await engine.unregister(consumerID)
        let final = await engine.metricsSnapshot()
        assertDeliveryConservation(final, pendingBuffered: 0, "orderbook replacement")
    }

    func testCandleMergeIsCountedDistinctly() async {
        let (engine, transport, _) = makeEngine()
        let (consumerID, _) = await engine.register()
        await engine.replaceSubscriptions(owner: consumerID, with: [candlesBTC])
        let connection = try! XCTUnwrap(transport.lastConnection)
        connection.scriptOpened()
        connection.scriptText(RealtimeFixtureLoader.candleMessage(close: 100, candleTimeMillis: 1_700_000_000_000, sequence: 0))
        connection.scriptText(RealtimeFixtureLoader.candleMessage(close: 101, candleTimeMillis: 1_700_000_000_000, sequence: 1))
        await waitUntil { await engine.metricsSnapshot().messagesDecoded == 2 }

        let snapshot = await engine.metricsSnapshot()
        XCTAssertEqual(snapshot.candleUpdatesMergedOrReplaced, 1, "same-interval update merges into the pending one")
        XCTAssertEqual(snapshot.orderbookSnapshotsReplaced, 0)
        XCTAssertEqual(snapshot.tickerEventsCoalesced, 0)
        await engine.unregister(consumerID)
        let final = await engine.metricsSnapshot()
        assertDeliveryConservation(final, pendingBuffered: 0, "candle merge")
    }

    func testBoundedTradeDropsAreCountedAsTradeDrops() async {
        let (engine, transport, _) = makeEngine(maxTradeBatchesPerMarket: 2)
        let (consumerID, _) = await engine.register()
        await engine.replaceSubscriptions(owner: consumerID, with: [tradesBTC])
        let connection = try! XCTUnwrap(transport.lastConnection)
        connection.scriptOpened()
        for sequence in 0..<5 {
            connection.scriptText(RealtimeFixtureLoader.tradesMessage(price: 100 + Double(sequence), sequence: sequence))
        }
        await waitUntil { await engine.metricsSnapshot().messagesDecoded == 5 }

        let snapshot = await engine.metricsSnapshot()
        XCTAssertEqual(snapshot.tradeEventsDropped, 3, "oldest batches beyond the per-market bound are counted")
        XCTAssertEqual(snapshot.bufferEventsDropped, 0, "trade-bound drops are not capacity drops")
        await engine.unregister(consumerID)
        let final = await engine.metricsSnapshot()
        assertDeliveryConservation(final, pendingBuffered: 0, "bounded trade drops")
    }

    func testIngressConservationSeparatesDecodedControlAndFailures() async {
        let (engine, transport, _) = makeEngine()
        await engine.replaceSubscriptions(owner: UUID(), with: [tickerBTC])
        let connection = try! XCTUnwrap(transport.lastConnection)
        connection.scriptOpened()
        connection.scriptText(RealtimeFixtureLoader.tickerMessage(price: 100))
        connection.scriptText("{\"type\":\"pong\"}")
        connection.scriptText("not json at all")
        await waitUntil { await engine.metricsSnapshot().transportFramesReceived == 3 }

        let snapshot = await engine.metricsSnapshot()
        XCTAssertEqual(snapshot.messagesDecoded, 1)
        XCTAssertEqual(snapshot.controlMessages, 1)
        XCTAssertEqual(snapshot.decodeFailures, 1)
        XCTAssertEqual(
            snapshot.transportFramesReceived,
            snapshot.messagesDecoded + snapshot.controlMessages + snapshot.decodeFailures,
            "ingress conservation: every frame is decoded, control, or a counted failure"
        )
    }
}
