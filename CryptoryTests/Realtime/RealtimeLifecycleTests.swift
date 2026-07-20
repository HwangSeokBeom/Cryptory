import UIKit
import XCTest
@testable import Cryptory

/// Deterministic lifecycle tests: consumer-task cancellation must release
/// engine-side ownership, and `MarketStreamUIAdapter` must be deallocatable
/// and explicitly shut-downable without leaking consumers, subscriptions, or
/// sockets. No wall-clock sleeps: every wait is a bounded cooperative poll on
/// an exact condition (the deadline only guards against deadlock).
@MainActor
final class RealtimeLifecycleTests: XCTestCase {
    private let tickerBTC = PublicMarketSubscription(channel: .ticker, exchange: "upbit", symbol: "BTC")
    private let tickerETH = PublicMarketSubscription(channel: .ticker, exchange: "upbit", symbol: "ETH")

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

    private func engineDescription(_ engine: MarketStreamEngine) async -> String {
        let snapshot = await engine.metricsSnapshot()
        let consumers = await engine.debugConsumerCount
        return "state=\(snapshot.connectionState) consumers=\(consumers) upstream=\(snapshot.upstreamSubscriptionCount) dropped=\(snapshot.bufferEventsDropped)"
    }

    // MARK: - Consumer cancellation releases ownership

    func testConsumerCancellationWhileWaitingReleasesOwnershipAndClosesSocket() async {
        let (engine, transport, _) = makeEngine()
        let (consumerID, events) = await engine.register()
        await engine.replaceSubscriptions(owner: consumerID, with: [tickerBTC])
        let connection = try! XCTUnwrap(transport.lastConnection)
        connection.scriptOpened()
        await waitUntil { connection.sentMessages(action: "subscribe").count >= 1 }

        let consumerTask = Task { for await _ in events {} }
        await settle()
        consumerTask.cancel()
        _ = await consumerTask.value

        let released = await waitUntil { await engine.debugConsumerCount == 0 }
        let description = await engineDescription(engine)
        XCTAssertTrue(released, "cancellation must unregister the consumer; \(description)")
        let active = await engine.activeSubscriptions
        XCTAssertTrue(active.isEmpty, "cancellation must release registry ownership")
        let closed = await waitUntil { connection.isClosed }
        XCTAssertTrue(closed, "socket must close when the final owner's task is cancelled")
        let state = await waitUntil { await engine.currentState == .idle }
        XCTAssertTrue(state, "engine idles after the final owner leaves; \(description)")
    }

    func testCancellationBeforeFirstSuspensionStillReleasesOwnership() async {
        let (engine, transport, _) = makeEngine()
        let (consumerID, events) = await engine.register()
        await engine.replaceSubscriptions(owner: consumerID, with: [tickerBTC])
        transport.lastConnection?.scriptOpened()

        // Cancel before the consuming task ever runs: the cancellation lands
        // before (or during) waiter installation and must not be lost.
        let consumerTask = Task { for await _ in events {} }
        consumerTask.cancel()
        _ = await consumerTask.value

        let released = await waitUntil { await engine.debugConsumerCount == 0 }
        let description = await engineDescription(engine)
        XCTAssertTrue(released, "pre-suspension cancellation must unregister; \(description)")
        let active = await engine.activeSubscriptions
        XCTAssertTrue(active.isEmpty)
    }

    func testCancellationWithBufferedEventsCountsThemAsExplicitDrops() async {
        let (engine, transport, _) = makeEngine()
        let (consumerID, events) = await engine.register()
        await engine.replaceSubscriptions(owner: consumerID, with: [tickerBTC, tickerETH])
        let connection = try! XCTUnwrap(transport.lastConnection)
        connection.scriptOpened()
        // Two markets, two messages each: latest-per-market coalescing leaves
        // 2 market events pending, plus 2 connection-state events
        // (connecting, connected) that were dispatched to the never-pulling
        // consumer — 4 buffered events total.
        connection.scriptText(RealtimeFixtureLoader.tickerMessage(symbol: "BTC", price: 100, sequence: 0))
        connection.scriptText(RealtimeFixtureLoader.tickerMessage(symbol: "ETH", price: 10, sequence: 1))
        connection.scriptText(RealtimeFixtureLoader.tickerMessage(symbol: "BTC", price: 101, sequence: 2))
        connection.scriptText(RealtimeFixtureLoader.tickerMessage(symbol: "ETH", price: 11, sequence: 3))
        await waitUntil { await engine.metricsSnapshot().messagesDecoded == 4 }

        let droppedBefore = await engine.metricsSnapshot().bufferEventsDropped
        let consumerTask = Task { for await _ in events {} }
        consumerTask.cancel()
        _ = await consumerTask.value

        let released = await waitUntil { await engine.debugConsumerCount == 0 }
        let description = await engineDescription(engine)
        XCTAssertTrue(released, description)
        let snapshot = await engine.metricsSnapshot()
        XCTAssertEqual(
            snapshot.bufferEventsDropped - droppedBefore,
            4,
            "buffered events discarded by cancellation are explicit, counted drops; \(description)"
        )
    }

    func testCancellingOneOfTwoOwnersKeepsSocketThenFinalOwnerCloses() async {
        let (engine, transport, _) = makeEngine()
        let (firstID, firstEvents) = await engine.register()
        let (secondID, secondEvents) = await engine.register()
        await engine.replaceSubscriptions(owner: firstID, with: [tickerBTC])
        await engine.replaceSubscriptions(owner: secondID, with: [tickerBTC])
        let connection = try! XCTUnwrap(transport.lastConnection)
        connection.scriptOpened()
        await waitUntil { connection.sentMessages(action: "subscribe").count >= 1 }

        let firstTask = Task { for await _ in firstEvents {} }
        let secondTask = Task { for await _ in secondEvents {} }
        await settle()

        firstTask.cancel()
        _ = await firstTask.value
        let oneLeft = await waitUntil { await engine.debugConsumerCount == 1 }
        let description = await engineDescription(engine)
        XCTAssertTrue(oneLeft, description)
        XCTAssertFalse(connection.isClosed, "socket stays while another owner remains")
        var snapshot = await engine.metricsSnapshot()
        XCTAssertEqual(snapshot.upstreamSubscriptionCount, 1, "shared subscription survives one owner leaving")
        XCTAssertEqual(connection.sentMessages(action: "unsubscribe").count, 0)

        secondTask.cancel()
        _ = await secondTask.value
        let allGone = await waitUntil { await engine.debugConsumerCount == 0 }
        XCTAssertTrue(allGone)
        let closed = await waitUntil { connection.isClosed }
        XCTAssertTrue(closed, "final owner's cancellation closes the socket")
        snapshot = await engine.metricsSnapshot()
        XCTAssertEqual(snapshot.upstreamSubscriptionCount, 0)
    }

    func testCancellationFollowedByExplicitUnregisterIsIdempotent() async {
        let (engine, transport, _) = makeEngine()
        let (consumerID, events) = await engine.register()
        await engine.replaceSubscriptions(owner: consumerID, with: [tickerBTC])
        transport.lastConnection?.scriptOpened()

        let consumerTask = Task { for await _ in events {} }
        await settle()
        consumerTask.cancel()
        _ = await consumerTask.value
        await waitUntil { await engine.debugConsumerCount == 0 }
        let droppedAfterCancel = await engine.metricsSnapshot().bufferEventsDropped

        await engine.unregister(consumerID)
        let consumers = await engine.debugConsumerCount
        XCTAssertEqual(consumers, 0)
        let snapshot = await engine.metricsSnapshot()
        XCTAssertEqual(snapshot.bufferEventsDropped, droppedAfterCancel, "second release must not double-count drops")
    }

    // MARK: - Adapter lifecycle

    func testAdapterShutdownReleasesConsumerSubscriptionsAndConnection() async {
        let (engine, transport, _) = makeEngine()
        let adapter = MarketStreamUIAdapter(engine: engine, observesAppLifecycle: false)
        adapter.updateSubscriptions([tickerBTC])
        let opened = await waitUntil { transport.openCount == 1 }
        XCTAssertTrue(opened)
        let connection = try! XCTUnwrap(transport.lastConnection)
        connection.scriptOpened()
        await waitUntil { connection.sentMessages(action: "subscribe").count >= 1 }

        adapter.shutdown()
        let released = await waitUntil { await engine.debugConsumerCount == 0 }
        let description = await engineDescription(engine)
        XCTAssertTrue(released, "shutdown must unregister the engine consumer; \(description)")
        let closed = await waitUntil { connection.isClosed }
        XCTAssertTrue(closed, "shutdown of the only owner must close the socket")
        let active = await engine.activeSubscriptions
        XCTAssertTrue(active.isEmpty, "subscriptions released on shutdown")

        // Repeated shutdown is safe, and commands are no longer accepted.
        adapter.shutdown()
        adapter.shutdown()
        adapter.updateSubscriptions([tickerETH])
        await settle()
        XCTAssertEqual(transport.openCount, 1, "no commands accepted after shutdown")
    }

    func testDroppingLastAdapterReferenceDeallocatesAndReleasesEngineOwnership() async {
        let (engine, transport, _) = makeEngine()
        var adapter: MarketStreamUIAdapter? = MarketStreamUIAdapter(engine: engine, observesAppLifecycle: false)
        weak let weakAdapter = adapter
        adapter?.updateSubscriptions([tickerBTC])
        let opened = await waitUntil { transport.openCount == 1 }
        XCTAssertTrue(opened)
        let connection = try! XCTUnwrap(transport.lastConnection)
        connection.scriptOpened()
        await waitUntil { connection.sentMessages(action: "subscribe").count >= 1 }

        // Deliver one event so the consume loop has demonstrably run (and is
        // now suspended awaiting the next event without retaining self).
        var tickerCount = 0
        adapter?.onTickerReceived = { _ in tickerCount += 1 }
        connection.scriptText(RealtimeFixtureLoader.tickerMessage(price: 100))
        let delivered = await waitUntil { tickerCount == 1 }
        XCTAssertTrue(delivered, "consume loop delivers before the reference is dropped")

        adapter = nil
        let deallocated = await waitUntil { weakAdapter == nil }
        XCTAssertTrue(deallocated, "no task may keep the adapter alive while the stream is idle")
        let released = await waitUntil { await engine.debugConsumerCount == 0 }
        let description = await engineDescription(engine)
        XCTAssertTrue(released, "deallocation releases the engine consumer; \(description)")
        let closed = await waitUntil { connection.isClosed }
        XCTAssertTrue(closed, "socket closes once the deallocated adapter's ownership is released")
    }

    func testCallbacksAreNotDeliveredAfterShutdown() async {
        let (engine, transport, _) = makeEngine()
        let adapter = MarketStreamUIAdapter(engine: engine, observesAppLifecycle: false)
        var tickerCount = 0
        adapter.onTickerReceived = { _ in tickerCount += 1 }
        adapter.updateSubscriptions([tickerBTC])
        let opened = await waitUntil { transport.openCount == 1 }
        XCTAssertTrue(opened)
        let connection = try! XCTUnwrap(transport.lastConnection)
        connection.scriptOpened()
        await waitUntil { connection.sentMessages(action: "subscribe").count >= 1 }
        connection.scriptText(RealtimeFixtureLoader.tickerMessage(price: 100))
        let delivered = await waitUntil { tickerCount == 1 }
        XCTAssertTrue(delivered)

        adapter.shutdown()
        await waitUntil { await engine.debugConsumerCount == 0 }
        connection.scriptText(RealtimeFixtureLoader.tickerMessage(price: 200))
        await settle()
        XCTAssertEqual(tickerCount, 1, "no callback may fire after shutdown")
    }

    // MARK: - MainActor delivery contract

    func testAdapterDeliversEventsInOrderOnMainActor() async {
        let (engine, transport, _) = makeEngine()
        let adapter = MarketStreamUIAdapter(engine: engine, observesAppLifecycle: false)
        var deliveredPrices: [Double] = []
        adapter.onTickerReceived = { payload in
            MainActor.assertIsolated("adapter callbacks are @MainActor by contract")
            deliveredPrices.append(payload.ticker.price)
        }
        adapter.updateSubscriptions([tickerBTC])
        let opened = await waitUntil { transport.openCount == 1 }
        XCTAssertTrue(opened)
        let connection = try! XCTUnwrap(transport.lastConnection)
        connection.scriptOpened()
        await waitUntil { connection.sentMessages(action: "subscribe").count >= 1 }

        connection.scriptText(RealtimeFixtureLoader.tickerMessage(price: 100, sequence: 0))
        let firstDelivered = await waitUntil { deliveredPrices.count == 1 }
        XCTAssertTrue(firstDelivered)
        connection.scriptText(RealtimeFixtureLoader.tickerMessage(price: 200, sequence: 1))
        let secondDelivered = await waitUntil { deliveredPrices.count == 2 }
        XCTAssertTrue(secondDelivered)
        connection.scriptText(RealtimeFixtureLoader.tickerMessage(price: 300, sequence: 2))
        let thirdDelivered = await waitUntil { deliveredPrices.count == 3 }
        XCTAssertTrue(thirdDelivered)
        XCTAssertEqual(deliveredPrices, [100, 200, 300], "delivery preserves event order")
        adapter.shutdown()
    }

    func testViewModelAppliesCallbackStateSynchronouslyOnMainActor() async {
        // The @MainActor callback contract lets CryptoViewModel apply state
        // without a per-event Task hop: after a synchronous emit, the state
        // must already be applied — no await, no runloop turn.
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

        XCTAssertNotEqual(vm.publicWebSocketState, .connected)
        service.emitState(.connected)
        XCTAssertEqual(
            vm.publicWebSocketState,
            .connected,
            "state must be applied synchronously within the MainActor callback"
        )
    }

    func testShutdownRemovesLifecycleObservers() async {
        let (engine, transport, _) = makeEngine()
        let adapter = MarketStreamUIAdapter(engine: engine, observesAppLifecycle: true)
        XCTAssertEqual(adapter.debugLifecycleObserverCount, 2)
        adapter.updateSubscriptions([tickerBTC])
        let opened = await waitUntil { transport.openCount == 1 }
        XCTAssertTrue(opened)

        // Observers work before shutdown: backgrounding suspends the engine.
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        let suspendedState = await waitUntil { await engine.currentState == .suspended }
        let description = await engineDescription(engine)
        XCTAssertTrue(suspendedState, "background notification suspends before shutdown; \(description)")

        adapter.shutdown()
        XCTAssertEqual(adapter.debugLifecycleObserverCount, 0, "shutdown removes lifecycle observers")
        XCTAssertTrue(adapter.debugIsShutdown)
    }
}
