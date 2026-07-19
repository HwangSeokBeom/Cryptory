import XCTest
@testable import Cryptory

/// Deterministic regression tests for complete realtime market identity:
/// coalescing keys carry exchange + quote + symbol, at most one quote
/// identity is live per (channel, exchange, symbol, interval), quote
/// replacement is atomic, and late events from a replaced identity are
/// discarded by token validation instead of being attributed to the newly
/// selected quote. These tests fail if the identity correction is reverted.
final class MarketIdentityTests: XCTestCase {
    private let identityBTCKRW = MarketIdentity(exchange: .upbit, symbol: "BTC", quoteCurrency: .krw)
    private let identityBTCUSDT = MarketIdentity(exchange: .upbit, symbol: "BTC", quoteCurrency: .usdt)
    private let identityETHKRW = MarketIdentity(exchange: .upbit, symbol: "ETH", quoteCurrency: .krw)

    private var tickerBTCKRW: PublicMarketSubscription {
        PublicMarketSubscription(channel: .ticker, marketIdentity: identityBTCKRW)
    }

    private var tickerBTCUSDT: PublicMarketSubscription {
        PublicMarketSubscription(channel: .ticker, marketIdentity: identityBTCUSDT)
    }

    private var tickerETHKRW: PublicMarketSubscription {
        PublicMarketSubscription(channel: .ticker, marketIdentity: identityETHKRW)
    }

    private var candlesBTCKRW: PublicMarketSubscription {
        PublicMarketSubscription(channel: .candles, marketIdentity: identityBTCKRW, interval: "1h")
    }

    private var candlesBTCUSDT: PublicMarketSubscription {
        PublicMarketSubscription(channel: .candles, marketIdentity: identityBTCUSDT, interval: "1h")
    }

    private func makeEngine() -> (MarketStreamEngine, ScriptedWebSocketTransport, ManualTestClock) {
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

    private func settle(yields: Int = 500) async {
        for _ in 0..<yields {
            await Task.yield()
        }
    }

    // MARK: - Wire contract

    func testParserExtractsEchoedQuoteCurrencyFromEnvelope() {
        let message = RealtimeFixtureLoader.tickerMessage(price: 100, quote: "KRW")
        guard case .ticker(let payload)? = MarketWebSocketMessageParser.parse(message) else {
            return XCTFail("fixture must decode as a ticker")
        }
        XCTAssertEqual(payload.quoteCurrency, .krw, "envelope quote echo must reach the payload identity")
    }

    func testParserLeavesQuoteNilWhenGatewayDoesNotEchoIt() {
        let message = RealtimeFixtureLoader.tickerMessage(price: 100)
        guard case .ticker(let payload)? = MarketWebSocketMessageParser.parse(message) else {
            return XCTFail("fixture must decode as a ticker")
        }
        XCTAssertNil(payload.quoteCurrency, "no invented quote when the wire does not carry one")
    }

    // MARK: - Coalescing keys carry the complete identity

    func testSameExchangeSymbolDifferentQuoteNeverShareACoalescingKey() {
        var buffer = MarketStreamEventBuffer()
        let krw = MarketStreamEvent.ticker(
            TickerStreamPayload(symbol: "BTC", exchange: "upbit", ticker: makeTicker(price: 100), quoteCurrency: .krw)
        )
        let usdt = MarketStreamEvent.ticker(
            TickerStreamPayload(symbol: "BTC", exchange: "upbit", ticker: makeTicker(price: 70_000), quoteCurrency: .usdt)
        )
        XCTAssertNotEqual(krw.coalescingKey, usdt.coalescingKey, "quote must be part of the coalescing key")

        var result = buffer.enqueue(krw, at: .zero, capacity: 16, maxTradeBatchesPerMarket: 4)
        XCTAssertFalse(result.coalescedTicker)
        result = buffer.enqueue(usdt, at: .zero, capacity: 16, maxTradeBatchesPerMarket: 4)
        XCTAssertFalse(result.coalescedTicker, "a different quote identity must never replace the pending event")
        XCTAssertEqual(buffer.count, 2, "both identities stay pending")

        // Same complete identity still coalesces.
        let newerKRW = MarketStreamEvent.ticker(
            TickerStreamPayload(symbol: "BTC", exchange: "upbit", ticker: makeTicker(price: 101), quoteCurrency: .krw)
        )
        result = buffer.enqueue(newerKRW, at: .zero, capacity: 16, maxTradeBatchesPerMarket: 4)
        XCTAssertTrue(result.coalescedTicker, "identical complete identity keeps coalescing")
        XCTAssertEqual(buffer.count, 2)

        var prices: [MarketQuoteCurrency?: Double] = [:]
        while let queued = buffer.dequeue() {
            if case .ticker(let payload) = queued.event {
                prices[payload.quoteCurrency] = payload.ticker.price
            }
        }
        XCTAssertEqual(prices[.krw], 101, "KRW pending event coalesced to the newest KRW value")
        XCTAssertEqual(prices[.usdt], 70_000, "USDT pending event untouched by KRW coalescing")
    }

    func testSameCompleteIdentityStillCoalescesThroughEngine() async {
        let (engine, transport, _) = makeEngine()
        let (consumerID, events) = await engine.register()
        var iterator = events.makeAsyncIterator()
        await engine.replaceSubscriptions(owner: consumerID, with: [tickerBTCKRW])
        let connection = try! XCTUnwrap(transport.lastConnection)
        connection.scriptOpened()

        for index in 0..<3 {
            connection.scriptText(
                RealtimeFixtureLoader.tickerMessage(price: 100 + Double(index), sequence: index, quote: "KRW")
            )
        }
        await waitUntil { await engine.metricsSnapshot().messagesDecoded == 3 }

        var payload: TickerStreamPayload?
        for _ in 0..<50 {
            guard let event = await iterator.next() else { break }
            if case .ticker(let ticker) = event {
                payload = ticker
                break
            }
        }
        XCTAssertEqual(payload?.ticker.price, 102, "slow consumer sees the newest value of the identity")
        XCTAssertEqual(payload?.quoteCurrency, .krw)
        let snapshot = await engine.metricsSnapshot()
        XCTAssertEqual(snapshot.tickerEventsCoalesced, 2)
        XCTAssertEqual(snapshot.staleIdentityEventsDropped, 0)
        await engine.unregister(consumerID)
    }

    func testQuoteBearingCandleMergePreservesIdentityThroughEngineDelivery() async {
        let (engine, transport, _) = makeEngine()
        let (consumerID, events) = await engine.register()
        var iterator = events.makeAsyncIterator()
        await engine.replaceSubscriptions(owner: consumerID, with: [candlesBTCKRW])
        let connection = try! XCTUnwrap(transport.lastConnection)
        connection.scriptOpened()

        connection.scriptText(
            RealtimeFixtureLoader.candleMessage(
                close: 100,
                candleTimeMillis: 1_700_000_000_000,
                sequence: 0,
                quote: "KRW"
            )
        )
        connection.scriptText(
            RealtimeFixtureLoader.candleMessage(
                close: 101,
                candleTimeMillis: 1_700_003_600_000,
                sequence: 1,
                quote: "KRW"
            )
        )
        await waitUntil { await engine.metricsSnapshot().messagesDecoded == 2 }

        var payload: CandleStreamPayload?
        for _ in 0..<50 {
            guard let event = await iterator.next() else { break }
            if case .candles(let candles) = event {
                payload = candles
                break
            }
        }
        XCTAssertEqual(payload?.quoteCurrency, .krw, "engine coalescing must preserve the stamped quote")
        XCTAssertEqual(payload?.candles.map(\.close), [100, 101])
        let snapshot = await engine.metricsSnapshot()
        XCTAssertEqual(snapshot.candleUpdatesMergedOrReplaced, 1)
        XCTAssertEqual(snapshot.staleIdentityEventsDropped, 0)
        await engine.unregister(consumerID)
    }

    // MARK: - Single live identity per channel key

    func testConflictingQuoteIdentityIsEvictedAtomicallyFromRegistry() {
        var registry = MarketSubscriptionRegistry()
        let ownerA = UUID()
        let ownerB = UUID()

        let first = registry.replace(owner: ownerA, with: [tickerBTCKRW])
        XCTAssertEqual(first.subscribe, [tickerBTCKRW])
        XCTAssertTrue(first.unsubscribe.isEmpty)

        // A different quote for the same channel key replaces the previous
        // identity in one atomic diff: no interleaving where both are active.
        let second = registry.replace(owner: ownerB, with: [tickerBTCUSDT])
        XCTAssertEqual(second.subscribe, [tickerBTCUSDT])
        XCTAssertEqual(second.unsubscribe, [tickerBTCKRW], "the replaced identity unsubscribes upstream")
        XCTAssertEqual(registry.activeSubscriptions, [tickerBTCUSDT], "conflicting identities never coexist")

        // The evicted owner's later cleanup stays consistent.
        let cleanup = registry.removeOwner(ownerA)
        XCTAssertTrue(cleanup.isEmpty, "evicted subscription is already gone")
        XCTAssertEqual(registry.activeSubscriptions, [tickerBTCUSDT])
    }

    func testConflictWithinOneReplacementSetResolvesDeterministically() {
        // The same conflicting pair must resolve to the same winner on every
        // run regardless of Set iteration order (additions are sorted).
        var winners = Set<String>()
        for _ in 0..<20 {
            var registry = MarketSubscriptionRegistry()
            _ = registry.replace(owner: UUID(), with: [tickerBTCKRW, tickerBTCUSDT])
            let active = registry.activeSubscriptions
            XCTAssertEqual(active.count, 1, "conflicting identities in one set must not both survive")
            winners.insert(active.first?.quoteCurrency?.rawValue ?? "-")
        }
        XCTAssertEqual(winners.count, 1, "conflict resolution must be deterministic, got \(winners)")
    }

    // MARK: - Identity stamping and stale-identity discard

    func testUnstampedEventReceivesLiveSubscriptionIdentity() async {
        let (engine, transport, _) = makeEngine()
        let (consumerID, events) = await engine.register()
        var iterator = events.makeAsyncIterator()
        await engine.replaceSubscriptions(owner: consumerID, with: [tickerBTCKRW])
        let connection = try! XCTUnwrap(transport.lastConnection)
        connection.scriptOpened()

        connection.scriptText(RealtimeFixtureLoader.tickerMessage(price: 100))
        await waitUntil { await engine.metricsSnapshot().messagesDecoded == 1 }

        var payload: TickerStreamPayload?
        for _ in 0..<50 {
            guard let event = await iterator.next() else { break }
            if case .ticker(let ticker) = event {
                payload = ticker
                break
            }
        }
        XCTAssertEqual(payload?.ticker.price, 100)
        XCTAssertEqual(
            payload?.quoteCurrency,
            .krw,
            "quote-less wire events are stamped with the live subscription identity, not UI state"
        )
        await engine.unregister(consumerID)
    }

    func testLateEventFromReplacedQuoteIsDiscardedNotReattributed() async {
        let (engine, transport, _) = makeEngine()
        let (consumerID, events) = await engine.register()
        var iterator = events.makeAsyncIterator()
        await engine.replaceSubscriptions(owner: consumerID, with: [tickerBTCKRW])
        let connection = try! XCTUnwrap(transport.lastConnection)
        connection.scriptOpened()

        // A KRW-identity ticker is decoded and sits in the slow consumer's
        // buffer while the user switches the market to the USDT quote.
        connection.scriptText(RealtimeFixtureLoader.tickerMessage(price: 100, sequence: 0))
        await waitUntil { await engine.metricsSnapshot().messagesDecoded == 1 }
        await engine.replaceSubscriptions(owner: consumerID, with: [tickerBTCUSDT])
        connection.scriptText(RealtimeFixtureLoader.tickerMessage(price: 70_000, sequence: 1))
        await waitUntil { await engine.metricsSnapshot().messagesDecoded == 2 }

        // The first ticker the consumer sees must belong to the active
        // identity; the pre-replacement event is discarded by token
        // validation, never re-attributed to the new quote.
        var payload: TickerStreamPayload?
        for _ in 0..<50 {
            guard let event = await iterator.next() else { break }
            if case .ticker(let ticker) = event {
                payload = ticker
                break
            }
        }
        XCTAssertEqual(payload?.ticker.price, 70_000, "late KRW event must not surface after the quote switch")
        XCTAssertEqual(payload?.quoteCurrency, .usdt, "the delivered event carries the active identity")

        let snapshot = await engine.metricsSnapshot()
        XCTAssertEqual(snapshot.staleIdentityEventsDropped, 1, "the replaced-identity event is a counted drop")
        await engine.unregister(consumerID)

        // Delivery conservation with the stale-identity bucket included.
        let final = await engine.metricsSnapshot()
        XCTAssertEqual(
            final.consumerEnqueues,
            final.consumerDeliveries
                + final.tickerEventsCoalesced
                + final.orderbookSnapshotsReplaced
                + final.candleUpdatesMergedOrReplaced
                + final.tradeEventsDropped
                + final.bufferEventsDropped
                + final.staleIdentityEventsDropped,
            "metrics conservation must hold after identity replacement: \(final)"
        )
    }

    func testLateMergedCandleFromReplacedQuoteIsDroppedWithCorrectMetric() async {
        let (engine, transport, _) = makeEngine()
        let (consumerID, events) = await engine.register()
        var iterator = events.makeAsyncIterator()
        await engine.replaceSubscriptions(owner: consumerID, with: [candlesBTCKRW])
        let connection = try! XCTUnwrap(transport.lastConnection)
        connection.scriptOpened()

        connection.scriptText(
            RealtimeFixtureLoader.candleMessage(close: 100, candleTimeMillis: 1_700_000_000_000, sequence: 0)
        )
        connection.scriptText(
            RealtimeFixtureLoader.candleMessage(close: 101, candleTimeMillis: 1_700_003_600_000, sequence: 1)
        )
        await waitUntil { await engine.metricsSnapshot().messagesDecoded == 2 }
        await engine.replaceSubscriptions(owner: consumerID, with: [candlesBTCUSDT])
        connection.scriptText(
            RealtimeFixtureLoader.candleMessage(close: 70_000, candleTimeMillis: 1_700_007_200_000, sequence: 2)
        )
        await waitUntil { await engine.metricsSnapshot().messagesDecoded == 3 }

        var delivered: CandleStreamPayload?
        for _ in 0..<50 {
            guard let event = await iterator.next() else { break }
            if case .candles(let candles) = event {
                delivered = candles
                break
            }
        }
        XCTAssertEqual(delivered?.quoteCurrency, .usdt)
        XCTAssertEqual(delivered?.candles.map(\.close), [70_000])
        let snapshot = await engine.metricsSnapshot()
        XCTAssertEqual(snapshot.candleUpdatesMergedOrReplaced, 1, "the two KRW updates coalesced before replacement")
        XCTAssertEqual(snapshot.staleIdentityEventsDropped, 1, "the stale merged KRW entry is counted once")
        await engine.unregister(consumerID)
    }

    @MainActor
    func testMergedKRWCandleCannotUpdateUSDTChartAndQuoteLessCompatibilityRemains() {
        var buffer = MarketStreamEventBuffer()
        let older = CandleStreamPayload(
            symbol: "BTC",
            exchange: "binance",
            interval: "1h",
            candles: [CandleData(time: 1000, open: 1, high: 2, low: 0, close: 100, volume: 5)],
            quoteCurrency: .krw
        )
        let newer = CandleStreamPayload(
            symbol: "BTC",
            exchange: "binance",
            interval: "1h",
            candles: [CandleData(time: 2000, open: 2, high: 3, low: 1, close: 101, volume: 6)],
            quoteCurrency: .krw
        )
        _ = buffer.enqueue(.candles(older), at: .zero, capacity: 16, maxTradeBatchesPerMarket: 4)
        _ = buffer.enqueue(.candles(newer), at: .zero, capacity: 16, maxTradeBatchesPerMarket: 4)
        guard case .candles(let mergedKRW)? = buffer.dequeue()?.event else {
            return XCTFail("expected merged KRW candles")
        }
        XCTAssertEqual(mergedKRW.quoteCurrency, .krw)

        let service = ManualPublicWebSocketService()
        let vm = CryptoViewModel(
            marketRepository: SpyMarketRepository(),
            tradingRepository: SpyTradingRepository(),
            portfolioRepository: SpyPortfolioRepository(),
            kimchiPremiumRepository: StubKimchiPremiumRepository(),
            exchangeConnectionsRepository: SpyExchangeConnectionsRepository(),
            authService: StubAuthenticationService(),
            publicWebSocketService: service,
            privateWebSocketService: NoOpPrivateWebSocketService()
        )
        vm.updateExchange(.binance, source: "identity_test")
        vm.selectedCoin = CoinCatalog.coin(symbol: "BTC", exchange: .binance)
        vm.chartPeriod = "1h"
        XCTAssertEqual(vm.selectedQuoteCurrency, .usdt)

        service.emitCandles(mergedKRW)
        XCTAssertTrue(vm.candles.isEmpty, "a known KRW identity must not act as a wildcard on a USDT chart")

        service.emitCandles(
            CandleStreamPayload(
                symbol: "BTC",
                exchange: "binance",
                interval: "1h",
                candles: [CandleData(time: 3000, open: 3, high: 4, low: 2, close: 102, volume: 7)]
            )
        )
        XCTAssertEqual(vm.candles.map(\.close), [102], "quote-less gateway payloads retain legacy wildcard behavior")
    }

    func testWireEchoedQuoteConflictingWithLiveIdentityIsIgnoredAsStale() async {
        let (engine, transport, _) = makeEngine()
        let (consumerID, events) = await engine.register()
        var iterator = events.makeAsyncIterator()
        await engine.replaceSubscriptions(owner: consumerID, with: [tickerBTCUSDT])
        let connection = try! XCTUnwrap(transport.lastConnection)
        connection.scriptOpened()

        // A gateway frame still tagged with the replaced KRW identity arrives
        // after the switch: authoritative mismatch, discarded before fanout.
        let staleBefore = await engine.metricsSnapshot().staleEventsIgnored
        connection.scriptText(RealtimeFixtureLoader.tickerMessage(price: 100, sequence: 0, quote: "KRW"))
        connection.scriptText(RealtimeFixtureLoader.tickerMessage(price: 70_000, sequence: 1, quote: "USDT"))
        await waitUntil { await engine.metricsSnapshot().messagesDecoded == 2 }

        var payload: TickerStreamPayload?
        for _ in 0..<50 {
            guard let event = await iterator.next() else { break }
            if case .ticker(let ticker) = event {
                payload = ticker
                break
            }
        }
        XCTAssertEqual(payload?.ticker.price, 70_000, "only the active identity's event is delivered")
        XCTAssertEqual(payload?.quoteCurrency, .usdt)
        let snapshot = await engine.metricsSnapshot()
        XCTAssertEqual(snapshot.staleEventsIgnored, staleBefore + 1, "the mismatched wire identity is counted")
        await engine.unregister(consumerID)
    }

    func testDifferentSymbolsStayIndependentAcrossQuoteReplacement() async {
        let (engine, transport, _) = makeEngine()
        let (consumerID, events) = await engine.register()
        var iterator = events.makeAsyncIterator()
        await engine.replaceSubscriptions(owner: consumerID, with: [tickerBTCKRW, tickerETHKRW])
        let connection = try! XCTUnwrap(transport.lastConnection)
        connection.scriptOpened()

        // Both symbols buffer one event, then only BTC's quote is replaced.
        connection.scriptText(RealtimeFixtureLoader.tickerMessage(symbol: "ETH", price: 5_000, sequence: 0))
        connection.scriptText(RealtimeFixtureLoader.tickerMessage(symbol: "BTC", price: 100, sequence: 1))
        await waitUntil { await engine.metricsSnapshot().messagesDecoded == 2 }
        await engine.replaceSubscriptions(owner: consumerID, with: [tickerBTCUSDT, tickerETHKRW])
        // Post-replacement BTC/USDT sentinel: it queues behind the stale
        // BTC/KRW entry (different coalescing key), so draining up to it
        // forces the stale entry through the dequeue-time validation.
        connection.scriptText(RealtimeFixtureLoader.tickerMessage(symbol: "BTC", price: 70_000, sequence: 2))
        await waitUntil { await engine.metricsSnapshot().messagesDecoded == 3 }

        var deliveredBySymbol: [String: [TickerStreamPayload]] = [:]
        for _ in 0..<50 {
            guard let event = await iterator.next() else { break }
            if case .ticker(let payload) = event {
                deliveredBySymbol[payload.symbol, default: []].append(payload)
            }
            if deliveredBySymbol["BTC"] != nil { break }
        }

        XCTAssertEqual(
            deliveredBySymbol["ETH"]?.map(\.ticker.price),
            [5_000],
            "the untouched symbol's pending event survives the other market's replacement"
        )
        XCTAssertEqual(deliveredBySymbol["ETH"]?.first?.quoteCurrency, .krw)
        XCTAssertEqual(
            deliveredBySymbol["BTC"]?.map(\.ticker.price),
            [70_000],
            "only the active BTC identity's event is delivered; the replaced one is discarded"
        )
        XCTAssertEqual(deliveredBySymbol["BTC"]?.first?.quoteCurrency, .usdt)
        let snapshot = await engine.metricsSnapshot()
        XCTAssertEqual(snapshot.staleIdentityEventsDropped, 1)
        await engine.unregister(consumerID)
    }

    // MARK: - Helpers

    private func makeTicker(price: Double) -> TickerData {
        TickerData(
            price: price,
            change: 1.0,
            volume: 10,
            high24: price,
            low24: price
        )
    }
}
