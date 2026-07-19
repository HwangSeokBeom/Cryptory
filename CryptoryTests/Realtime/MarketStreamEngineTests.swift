import XCTest
@testable import Cryptory

/// Deterministic integration tests for `MarketStreamEngine` using
/// `ScriptedWebSocketTransport` and `ManualTestClock`. No live network, no
/// wall-clock sleeps for correctness; every wait is a bounded cooperative
/// poll or a manual clock advance.
final class MarketStreamEngineTests: XCTestCase {
    private let tickerBTC = PublicMarketSubscription(channel: .ticker, exchange: "upbit", symbol: "BTC")
    private let tickerETH = PublicMarketSubscription(channel: .ticker, exchange: "upbit", symbol: "ETH")
    private let tradesBTC = PublicMarketSubscription(channel: .trades, exchange: "upbit", symbol: "BTC")

    private func makeEngine(
        reconnectPolicy: ReconnectPolicy = ReconnectPolicy(
            initialDelay: .seconds(1),
            multiplier: 2,
            maxDelay: .seconds(30),
            jitterRatio: 0.2
        ),
        heartbeatPolicy: HeartbeatPolicy = HeartbeatPolicy(),
        bufferCapacity: Int = 1024,
        maxTradeBatchesPerMarket: Int = 64,
        jitterUnit: Double = 0.5
    ) -> (MarketStreamEngine, ScriptedWebSocketTransport, ManualTestClock) {
        let transport = ScriptedWebSocketTransport()
        let clock = ManualTestClock()
        let engine = MarketStreamEngine(
            url: URL(string: "wss://unit.test/ws/market")!,
            transport: transport,
            clock: clock,
            reconnectPolicy: reconnectPolicy,
            heartbeatPolicy: heartbeatPolicy,
            bufferCapacity: bufferCapacity,
            maxTradeBatchesPerMarket: maxTradeBatchesPerMarket,
            jitter: { jitterUnit }
        )
        return (engine, transport, clock)
    }

    /// Bounded cooperative wait. The condition is the synchronization; the
    /// wall-clock deadline only guards against deadlock (returning false
    /// instead of hanging). A yield-count bound proved scheduler-dependent
    /// under full-suite load.
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

    /// Lets in-flight actor jobs run; used before negative assertions.
    private func settle(yields: Int = 500) async {
        for _ in 0..<yields {
            await Task.yield()
        }
    }

    private func engineStateDescription(_ engine: MarketStreamEngine) async -> String {
        let snapshot = await engine.metricsSnapshot()
        return "state=\(snapshot.connectionState) gen=\(snapshot.generation) frames=\(snapshot.transportFramesReceived) decoded=\(snapshot.messagesDecoded) dropped=\(snapshot.tradeEventsDropped + snapshot.bufferEventsDropped) reconnects=\(snapshot.reconnectCount) hbSuccess=\(snapshot.heartbeatSuccessCount) hbFailure=\(snapshot.heartbeatFailureCount) stale=\(snapshot.staleEventsIgnored)"
    }

    /// XCTAssertTrue variant whose failure message includes engine state
    /// (async work is not allowed inside XCTest autoclosure messages).
    private func assertTrue(
        _ value: Bool,
        engine: MarketStreamEngine,
        _ note: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        if !value {
            let description = await engineStateDescription(engine)
            XCTFail("\(note) \(description)", file: file, line: line)
        }
    }

    /// Asserts that at least `count` tasks reach a suspension on the manual
    /// clock (async work is not allowed inside XCTest autoclosure messages).
    private func expectSleepers(
        _ clock: ManualTestClock,
        atLeast count: Int = 1,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let armed = await clock.waitForSleepers(atLeast: count)
        XCTAssertTrue(armed, "expected a pending clock timer", file: file, line: line)
    }

    /// Waits until the engine is in `.waitingToReconnect` (optionally for a
    /// specific attempt number) with its reconnect timer armed on the manual
    /// clock. Needed because the heartbeat timer is also a clock sleeper.
    @discardableResult
    private func waitForReconnectPending(
        _ engine: MarketStreamEngine,
        _ clock: ManualTestClock,
        attempt expectedAttempt: Int? = nil
    ) async -> Bool {
        await waitUntil {
            guard case .waitingToReconnect(_, let attempt, _) = await engine.currentState else { return false }
            if let expectedAttempt, attempt != expectedAttempt { return false }
            return clock.sleeperCount >= 1
        }
    }

    // MARK: - Connection ownership

    func testDuplicateConnectCreatesOneTransportConnection() async {
        let (engine, transport, _) = makeEngine()
        await engine.replaceSubscriptions(owner: UUID(), with: [tickerBTC])
        await engine.connect()
        await engine.connect()
        let description = await engineStateDescription(engine)
        XCTAssertEqual(transport.openCount, 1, description)
    }

    func testRepeatedDisconnectIsSafe() async {
        let (engine, transport, _) = makeEngine()
        await engine.replaceSubscriptions(owner: UUID(), with: [tickerBTC])
        transport.lastConnection?.scriptOpened()
        await engine.disconnect()
        await engine.disconnect()
        await engine.disconnect()
        let state = await engine.currentState
        XCTAssertEqual(state, .idle)
        XCTAssertEqual(transport.openCount, 1)
    }

    func testConnectAfterDisconnectCreatesOneNewGeneration() async {
        let (engine, transport, _) = makeEngine()
        await engine.replaceSubscriptions(owner: UUID(), with: [tickerBTC])
        let generationBefore = await engine.metricsSnapshot().generation
        XCTAssertEqual(generationBefore, 1)

        await engine.disconnect()
        await engine.connect()

        let generationAfter = await engine.metricsSnapshot().generation
        XCTAssertEqual(generationAfter, 2)
        XCTAssertEqual(transport.openCount, 2)
    }

    // MARK: - Subscription ownership over the wire

    func testTwoOwnersOfOneSubscriptionProduceOneUpstreamSubscribe() async {
        let (engine, transport, _) = makeEngine()
        await engine.replaceSubscriptions(owner: UUID(), with: [tickerBTC])
        await engine.replaceSubscriptions(owner: UUID(), with: [tickerBTC])
        let connection = try! XCTUnwrap(transport.lastConnection)
        connection.scriptOpened()

        let delivered = await waitUntil { connection.sentMessages(action: "subscribe").count >= 1 }
        await assertTrue(delivered, engine: engine)
        await settle()
        XCTAssertEqual(connection.sentMessages(action: "subscribe").count, 1)
    }

    func testRemovingOneOwnerDoesNotUnsubscribePrematurelyAndFinalOwnerUnsubscribesOnce() async {
        let (engine, transport, _) = makeEngine()
        let ownerA = UUID()
        let ownerB = UUID()
        await engine.replaceSubscriptions(owner: ownerA, with: [tickerBTC, tickerETH])
        await engine.replaceSubscriptions(owner: ownerB, with: [tickerBTC])
        let connection = try! XCTUnwrap(transport.lastConnection)
        connection.scriptOpened()
        await waitUntil { connection.sentMessages(action: "subscribe").count >= 2 }

        // Removing one of two owners of the BTC ticker: no unsubscribe.
        await engine.replaceSubscriptions(owner: ownerB, with: [])
        // Sequencing point: a later subscribe proves earlier sends flushed.
        await engine.replaceSubscriptions(owner: ownerA, with: [tickerBTC, tickerETH, tradesBTC])
        await waitUntil { connection.sentMessages(action: "subscribe").count >= 3 }
        XCTAssertEqual(connection.sentMessages(action: "unsubscribe").count, 0)

        // Removing the final owner of everything: exactly one unsubscribe per
        // subscription, and the idle policy closes the socket.
        await engine.replaceSubscriptions(owner: ownerA, with: [])
        await waitUntil { connection.isClosed }
        XCTAssertEqual(connection.sentMessages(action: "unsubscribe").count, 3)
        let state = await engine.currentState
        XCTAssertEqual(state, .idle)
    }

    func testZeroSubscriptionsDoNotKeepSocketAlive() async {
        let (engine, transport, clock) = makeEngine()
        let owner = UUID()
        await engine.replaceSubscriptions(owner: owner, with: [tickerBTC])
        let connection = try! XCTUnwrap(transport.lastConnection)
        connection.scriptOpened()
        await waitUntil { connection.sentMessages(action: "subscribe").count >= 1 }

        await engine.replaceSubscriptions(owner: owner, with: [])
        let closed = await waitUntil { connection.isClosed }
        await assertTrue(closed, engine: engine)

        // The stream-termination callback from our own close must not
        // schedule a reconnect (stale-failure suppression).
        await settle()
        clock.advance(by: .seconds(120))
        await settle()
        XCTAssertEqual(transport.openCount, 1)
        XCTAssertEqual(clock.sleeperCount, 0)
        let state = await engine.currentState
        XCTAssertEqual(state, .idle)
    }

    func testRapidSubscriptionReplacementConvergesToFinalSet() async {
        let (engine, transport, _) = makeEngine()
        let owner = UUID()
        await engine.replaceSubscriptions(owner: owner, with: [tickerBTC])
        let connection = try! XCTUnwrap(transport.lastConnection)
        connection.scriptOpened()

        await engine.replaceSubscriptions(owner: owner, with: [tickerETH])
        await engine.replaceSubscriptions(owner: owner, with: [tickerBTC, tradesBTC])
        await engine.replaceSubscriptions(owner: owner, with: [tradesBTC])

        let active = await engine.activeSubscriptions
        XCTAssertEqual(active, [tradesBTC])
        await waitUntil { connection.sentMessages(action: "subscribe").contains { $0.contains("\"channel\":\"trades\"") } }
        await settle()
        // Wire converges: net subscribe count is 1 for the final set and 0
        // for every superseded subscription (each may legitimately churn).
        func net(_ predicate: (String) -> Bool) -> Int {
            connection.sentMessages(action: "subscribe").filter(predicate).count
                - connection.sentMessages(action: "unsubscribe").filter(predicate).count
        }
        XCTAssertEqual(net { $0.contains("\"channel\":\"trades\"") }, 1)
        XCTAssertEqual(net { $0.contains("BTC") && $0.contains("\"channel\":\"ticker\"") }, 0)
        XCTAssertEqual(net { $0.contains("ETH") }, 0)
        XCTAssertEqual(connection.sentMessages(action: "subscribe").filter { $0.contains("\"channel\":\"trades\"") }.count, 1)
    }

    // MARK: - Reconnect

    func testReconnectReplaysActiveSubscriptionsExactlyOnce() async {
        let (engine, transport, clock) = makeEngine()
        await engine.replaceSubscriptions(owner: UUID(), with: [tickerBTC, tickerETH])
        let first = try! XCTUnwrap(transport.lastConnection)
        first.scriptOpened()
        await waitUntil { first.sentMessages(action: "subscribe").count >= 2 }

        first.scriptFailure()
        let waiting = await waitForReconnectPending(engine, clock, attempt: 1)
        await assertTrue(waiting, engine: engine)

        clock.advance(by: .seconds(1))
        let reopened = await waitUntil { transport.openCount == 2 }
        await assertTrue(reopened, engine: engine)

        let second = try! XCTUnwrap(transport.lastConnection)
        await waitUntil { second.sentMessages(action: "subscribe").count >= 2 }
        await settle()
        XCTAssertEqual(second.sentMessages(action: "subscribe").count, 2, "subscriptions replayed exactly once")
    }

    func testManualDisconnectSuppressesReconnect() async {
        let (engine, transport, clock) = makeEngine()
        await engine.replaceSubscriptions(owner: UUID(), with: [tickerBTC])
        let connection = try! XCTUnwrap(transport.lastConnection)
        connection.scriptOpened()

        await engine.disconnect()
        await settle()
        XCTAssertEqual(clock.sleeperCount, 0, "no reconnect timer after manual disconnect")

        clock.advance(by: .seconds(300))
        await settle()
        XCTAssertEqual(transport.openCount, 1)
        let state = await engine.currentState
        XCTAssertEqual(state, .idle)
    }

    func testExponentialBackoffIncreasesAndStabilityResetsOnlyAtDocumentedPoint() async {
        let (engine, transport, clock) = makeEngine()
        await engine.replaceSubscriptions(owner: UUID(), with: [tickerBTC])

        // Attempt 1: fail before the connection proves useful → 1s backoff.
        transport.connections[0].scriptOpened()
        transport.connections[0].scriptFailure()
        let firstPending = await waitForReconnectPending(engine, clock, attempt: 1)
        await assertTrue(firstPending, engine: engine, "attempt 1 pending")
        var snapshot = await engine.metricsSnapshot()
        XCTAssertEqual(snapshot.consecutiveReconnectFailures, 1)

        // Merely opening did not reset backoff: attempt 2 waits 2s, not 1s.
        clock.advance(by: .seconds(1))
        await waitUntil { transport.openCount == 2 }
        transport.connections[1].scriptOpened()
        transport.connections[1].scriptFailure()
        let secondPending = await waitForReconnectPending(engine, clock, attempt: 2)
        await assertTrue(secondPending, engine: engine, "attempt 2 pending")
        snapshot = await engine.metricsSnapshot()
        XCTAssertEqual(snapshot.consecutiveReconnectFailures, 2)

        clock.advance(by: .seconds(1))
        await settle()
        XCTAssertEqual(transport.openCount, 2, "attempt 2 must wait the full 2s")
        clock.advance(by: .seconds(1))
        await waitUntil { transport.openCount == 3 }

        // Deliver a decoded market event: documented stability point.
        transport.connections[2].scriptOpened()
        transport.connections[2].scriptText(RealtimeFixtureLoader.tickerMessage(price: 100))
        await waitUntil { await engine.metricsSnapshot().consecutiveReconnectFailures == 0 }

        // Next failure starts over at attempt 1 (1s delay).
        transport.connections[2].scriptFailure()
        let resetPending = await waitForReconnectPending(engine, clock, attempt: 1)
        await assertTrue(resetPending, engine: engine, "attempt reset pending")
        clock.advance(by: .seconds(1))
        let reopened = await waitUntil { transport.openCount == 4 }
        XCTAssertTrue(reopened, "backoff reset after stability → 1s delay again")
    }

    func testBackoffIsCappedAtMaximumDelay() async {
        let (engine, transport, clock) = makeEngine(
            reconnectPolicy: ReconnectPolicy(
                initialDelay: .seconds(1),
                multiplier: 2,
                maxDelay: .seconds(4),
                jitterRatio: 0.2
            )
        )
        await engine.replaceSubscriptions(owner: UUID(), with: [tickerBTC])

        // Fail 4 times without stability; delays: 1, 2, 4, 4 (capped).
        for attempt in 1...4 {
            let connection = transport.connections[attempt - 1]
            connection.scriptFailure()
            let sleeping = await clock.waitForSleepers(atLeast: 1)
            await assertTrue(sleeping, engine: engine, "attempt \(attempt)")
            let expected: Duration = attempt >= 3 ? .seconds(4) : .seconds(attempt == 1 ? 1 : 2)
            clock.advance(by: expected)
            let reopened = await waitUntil { transport.openCount == attempt + 1 }
            XCTAssertTrue(reopened, "attempt \(attempt) should reconnect after \(expected)")
        }
    }

    // MARK: - Backoff preservation during subscription churn

    func testSameSubscriptionSetWhileWaitingToReconnectPreservesBackoffTimer() async {
        let (engine, transport, clock) = makeEngine()
        let owner = UUID()
        await engine.replaceSubscriptions(owner: owner, with: [tickerBTC])
        let first = try! XCTUnwrap(transport.lastConnection)
        first.scriptOpened()
        first.scriptFailure()
        let waiting = await waitForReconnectPending(engine, clock, attempt: 1)
        await assertTrue(waiting, engine: engine, "attempt 1 pending")

        // A same-set refresh during the outage (e.g. the UI re-applying its
        // subscriptions) must neither connect nor reset the timer.
        await engine.replaceSubscriptions(owner: owner, with: [tickerBTC])
        await settle()
        XCTAssertEqual(transport.openCount, 1, "same-set update must not bypass the reconnect wait")
        guard case .waitingToReconnect(_, let attempt, _) = await engine.currentState else {
            let description = await engineStateDescription(engine)
            return XCTFail("expected waitingToReconnect; \(description)")
        }
        XCTAssertEqual(attempt, 1, "backoff attempt must not reset")
        XCTAssertEqual(clock.sleeperCount, 1, "reconnect timer must remain armed")

        clock.advance(by: .seconds(1))
        let reopened = await waitUntil { transport.openCount == 2 }
        await assertTrue(reopened, engine: engine, "timer fire connects")
        let second = try! XCTUnwrap(transport.lastConnection)
        await waitUntil { second.sentMessages(action: "subscribe").count >= 1 }
        await settle()
        XCTAssertEqual(second.sentMessages(action: "subscribe").count, 1, "final set replayed exactly once")
    }

    func testChangedSubscriptionSetWhileWaitingToReconnectReconcilesWithoutConnecting() async {
        let (engine, transport, clock) = makeEngine()
        let owner = UUID()
        await engine.replaceSubscriptions(owner: owner, with: [tickerBTC])
        let first = try! XCTUnwrap(transport.lastConnection)
        first.scriptOpened()
        first.scriptFailure()
        let waiting = await waitForReconnectPending(engine, clock, attempt: 1)
        await assertTrue(waiting, engine: engine)

        await engine.replaceSubscriptions(owner: owner, with: [tickerETH])
        await settle()
        XCTAssertEqual(transport.openCount, 1, "changed set must not bypass the reconnect wait")
        let active = await engine.activeSubscriptions
        XCTAssertEqual(active, [tickerETH], "registry ownership reconciles while waiting")

        clock.advance(by: .seconds(1))
        let reopened = await waitUntil { transport.openCount == 2 }
        await assertTrue(reopened, engine: engine)
        let second = try! XCTUnwrap(transport.lastConnection)
        await waitUntil { second.sentMessages(action: "subscribe").count >= 1 }
        await settle()
        let subscribes = second.sentMessages(action: "subscribe")
        XCTAssertEqual(subscribes.count, 1, "exactly one replay of the final set")
        XCTAssertTrue(subscribes[0].contains("ETH"), "replay carries the final set, not the original")
        XCTAssertEqual(second.sentMessages(action: "unsubscribe").count, 0)
    }

    func testRapidSubscriptionChangesWhileWaitingToReconnectConvergeOnTimerFire() async {
        let (engine, transport, clock) = makeEngine()
        let owner = UUID()
        await engine.replaceSubscriptions(owner: owner, with: [tickerBTC])
        let first = try! XCTUnwrap(transport.lastConnection)
        first.scriptOpened()
        first.scriptFailure()
        let waiting = await waitForReconnectPending(engine, clock, attempt: 1)
        await assertTrue(waiting, engine: engine)

        await engine.replaceSubscriptions(owner: owner, with: [tickerETH])
        await engine.replaceSubscriptions(owner: owner, with: [tickerBTC, tradesBTC])
        await engine.replaceSubscriptions(owner: owner, with: [tradesBTC])
        await settle()
        XCTAssertEqual(transport.openCount, 1, "only one transport connection may exist before the timer fires")
        XCTAssertEqual(clock.sleeperCount, 1, "rapid churn must not cancel the reconnect timer")

        clock.advance(by: .seconds(1))
        let reopened = await waitUntil { transport.openCount == 2 }
        await assertTrue(reopened, engine: engine)
        let second = try! XCTUnwrap(transport.lastConnection)
        await waitUntil { second.sentMessages(action: "subscribe").count >= 1 }
        await settle()
        let subscribes = second.sentMessages(action: "subscribe")
        XCTAssertEqual(subscribes.count, 1, "converged final set replays exactly once")
        XCTAssertTrue(subscribes[0].contains("\"channel\":\"trades\""))
        XCTAssertEqual(second.sentMessages(action: "unsubscribe").count, 0)
    }

    func testExplicitConnectWhileWaitingToReconnectBypassesWaitByDocumentedPolicy() async {
        let (engine, transport, clock) = makeEngine()
        await engine.replaceSubscriptions(owner: UUID(), with: [tickerBTC])
        let first = try! XCTUnwrap(transport.lastConnection)
        first.scriptOpened()
        first.scriptFailure()
        let waiting = await waitForReconnectPending(engine, clock, attempt: 1)
        await assertTrue(waiting, engine: engine)

        // Documented bypass: a deliberate connect() call skips the wait.
        await engine.connect()
        let reopened = await waitUntil { transport.openCount == 2 }
        await assertTrue(reopened, engine: engine, "explicit connect bypasses backoff")

        // The superseded timer must be cancelled — no third connection later.
        transport.connections[1].scriptOpened()
        await waitUntil { await engine.currentState.isConnected }
        clock.advance(by: .seconds(300))
        await settle()
        XCTAssertEqual(transport.openCount, 2, "cancelled backoff timer must not fire")
    }

    // MARK: - Idle-close convergence (A → [] → B)

    func testNewSubscriptionDuringSuspendedUnsubscribeSendCancelsIdleClose() async {
        let (engine, transport, _) = makeEngine()
        let owner = UUID()
        await engine.replaceSubscriptions(owner: owner, with: [tickerBTC])
        let connection = try! XCTUnwrap(transport.lastConnection)
        connection.scriptOpened()
        await waitUntil { connection.sentMessages(action: "subscribe").count >= 1 }

        connection.beginSuspendingSends()
        await engine.replaceSubscriptions(owner: owner, with: [])
        let suspended = await waitUntil { connection.suspendedSendCount == 1 }
        await assertTrue(suspended, engine: engine, "unsubscribe send suspended")
        var sender = await engine.debugSenderState()
        XCTAssertTrue(sender.closeWhenOutboxDrained, "empty registry arms the idle close")

        await engine.replaceSubscriptions(owner: owner, with: [tickerETH])
        sender = await engine.debugSenderState()
        XCTAssertFalse(sender.closeWhenOutboxDrained, "non-empty registry must cancel the pending idle close")

        connection.resumeSuspendedSends()
        let subscribedETH = await waitUntil {
            connection.sentMessages(action: "subscribe").contains { $0.contains("ETH") }
        }
        await assertTrue(subscribedETH, engine: engine)
        await settle()
        XCTAssertFalse(connection.isClosed, "socket must survive A → [] → B")
        XCTAssertEqual(transport.openCount, 1, "no reconnect is needed to recover")
        XCTAssertEqual(connection.sentMessages(action: "unsubscribe").count, 1)
        let active = await engine.activeSubscriptions
        XCTAssertEqual(active, [tickerETH])
        let snapshot = await engine.metricsSnapshot()
        XCTAssertEqual(snapshot.upstreamSubscriptionCount, 1)
        XCTAssertTrue(snapshot.connectionState.isConnected, "state, registry, and metrics agree")
    }

    func testReplacementDuringSuspendedSubscribeSendPreservesSocket() async {
        let (engine, transport, _) = makeEngine()
        transport.setSuspendSendsOnOpen(true)
        let owner = UUID()
        await engine.replaceSubscriptions(owner: owner, with: [tickerBTC])
        let connection = try! XCTUnwrap(transport.lastConnection)
        connection.scriptOpened()
        let suspended = await waitUntil { connection.suspendedSendCount == 1 }
        await assertTrue(suspended, engine: engine, "initial subscribe suspended")

        await engine.replaceSubscriptions(owner: owner, with: [])
        var sender = await engine.debugSenderState()
        XCTAssertTrue(sender.closeWhenOutboxDrained)
        await engine.replaceSubscriptions(owner: owner, with: [tickerETH])
        sender = await engine.debugSenderState()
        XCTAssertFalse(sender.closeWhenOutboxDrained)

        connection.resumeSuspendedSends()
        let subscribedETH = await waitUntil {
            connection.sentMessages(action: "subscribe").contains { $0.contains("ETH") }
        }
        await assertTrue(subscribedETH, engine: engine)
        await settle()
        XCTAssertFalse(connection.isClosed)
        XCTAssertEqual(transport.openCount, 1)
        let active = await engine.activeSubscriptions
        XCTAssertEqual(active, [tickerETH])
        let sent = connection.sentMessages
        XCTAssertEqual(sent.filter { $0.contains("\"action\":\"subscribe\"") && $0.contains("BTC") }.count, 1)
        XCTAssertEqual(sent.filter { $0.contains("\"action\":\"unsubscribe\"") && $0.contains("BTC") }.count, 1)
        XCTAssertEqual(sent.filter { $0.contains("\"action\":\"subscribe\"") && $0.contains("ETH") }.count, 1)
    }

    func testMultipleEmptyNonemptyTransitionsConvergeToFinalSet() async {
        let (engine, transport, _) = makeEngine()
        let owner = UUID()
        await engine.replaceSubscriptions(owner: owner, with: [tickerBTC])
        let connection = try! XCTUnwrap(transport.lastConnection)
        connection.scriptOpened()
        await waitUntil { connection.sentMessages(action: "subscribe").count >= 1 }

        connection.beginSuspendingSends()
        await engine.replaceSubscriptions(owner: owner, with: [])
        await engine.replaceSubscriptions(owner: owner, with: [tickerETH])
        await engine.replaceSubscriptions(owner: owner, with: [])
        await engine.replaceSubscriptions(owner: owner, with: [tradesBTC])
        let sender = await engine.debugSenderState()
        XCTAssertFalse(sender.closeWhenOutboxDrained, "final non-empty set cancels the idle close")

        connection.resumeSuspendedSends()
        let converged = await waitUntil {
            connection.sentMessages(action: "subscribe").contains { $0.contains("\"channel\":\"trades\"") }
        }
        await assertTrue(converged, engine: engine)
        await settle()
        XCTAssertFalse(connection.isClosed)
        XCTAssertEqual(transport.openCount, 1)
        let active = await engine.activeSubscriptions
        XCTAssertEqual(active, [tradesBTC])
        func net(_ predicate: (String) -> Bool) -> Int {
            connection.sentMessages(action: "subscribe").filter(predicate).count
                - connection.sentMessages(action: "unsubscribe").filter(predicate).count
        }
        XCTAssertEqual(net { $0.contains("\"channel\":\"trades\"") }, 1)
        XCTAssertEqual(net { $0.contains("BTC") && $0.contains("\"channel\":\"ticker\"") }, 0)
        XCTAssertEqual(net { $0.contains("ETH") }, 0)
    }

    func testIdleCloseStillHappensWhenRegistryStaysEmptyAcrossSuspendedSend() async {
        let (engine, transport, _) = makeEngine()
        let owner = UUID()
        await engine.replaceSubscriptions(owner: owner, with: [tickerBTC])
        let connection = try! XCTUnwrap(transport.lastConnection)
        connection.scriptOpened()
        await waitUntil { connection.sentMessages(action: "subscribe").count >= 1 }

        connection.beginSuspendingSends()
        await engine.replaceSubscriptions(owner: owner, with: [])
        let suspended = await waitUntil { connection.suspendedSendCount == 1 }
        await assertTrue(suspended, engine: engine)

        connection.resumeSuspendedSends()
        let closed = await waitUntil { connection.isClosed }
        await assertTrue(closed, engine: engine, "truly empty registry still closes after the drain")
        let state = await engine.currentState
        XCTAssertEqual(state, .idle)
    }

    // MARK: - Sender task ownership

    func testStaleSenderResumingSuccessfullyDoesNotClearNewSenderOwnership() async {
        let (engine, transport, clock) = makeEngine()
        transport.setSuspendSendsOnOpen(true)
        let owner = UUID()
        await engine.replaceSubscriptions(owner: owner, with: [tickerBTC])
        let first = try! XCTUnwrap(transport.lastConnection)
        first.scriptOpened()
        let firstSuspended = await waitUntil { first.suspendedSendCount == 1 }
        await assertTrue(firstSuspended, engine: engine, "sender 1 suspended in send")

        // Teardown while sender 1 is suspended (non-cooperative: the gate
        // ignores cancellation, like URLSession can).
        first.scriptFailure()
        let waiting = await waitForReconnectPending(engine, clock, attempt: 1)
        await assertTrue(waiting, engine: engine)
        clock.advance(by: .seconds(1))
        let reopened = await waitUntil { transport.openCount == 2 }
        await assertTrue(reopened, engine: engine)
        let second = try! XCTUnwrap(transport.lastConnection)
        second.scriptOpened()
        let secondSuspended = await waitUntil { second.suspendedSendCount == 1 }
        await assertTrue(secondSuspended, engine: engine, "sender 2 suspended in replayed subscribe")

        // Old sender resumes successfully after the new generation started.
        first.resumeSuspendedSends()
        await settle()
        let sender = await engine.debugSenderState()
        XCTAssertTrue(sender.hasSenderTask, "stale sender must not clear the new sender's ownership")

        // A later subscription update must not start a duplicate sender: the
        // owned sender 2 is still suspended, so no second suspended send may
        // appear on connection 2.
        await engine.replaceSubscriptions(owner: owner, with: [tickerBTC, tickerETH])
        await settle()
        XCTAssertEqual(second.suspendedSendCount, 1, "no duplicate sender may drain the outbox")

        second.resumeSuspendedSends()
        let drained = await waitUntil { second.sentMessages(action: "subscribe").count == 2 }
        await assertTrue(drained, engine: engine, "owned sender drains the queued update")
        await settle()
        let subscribes = second.sentMessages(action: "subscribe")
        XCTAssertEqual(subscribes.count, 2, "subscription replay and update sent exactly once each")
        XCTAssertTrue(subscribes[0].contains("BTC"), "replay precedes the later update")
        XCTAssertTrue(subscribes[1].contains("ETH"))
        XCTAssertEqual(transport.openCount, 2, "stale sender must not trigger reconnects")
    }

    func testStaleSenderResumingByThrowingDoesNotFailNewGeneration() async {
        let (engine, transport, clock) = makeEngine()
        transport.setSuspendSendsOnOpen(true)
        let owner = UUID()
        await engine.replaceSubscriptions(owner: owner, with: [tickerBTC])
        let first = try! XCTUnwrap(transport.lastConnection)
        first.scriptOpened()
        let firstSuspended = await waitUntil { first.suspendedSendCount == 1 }
        await assertTrue(firstSuspended, engine: engine)

        first.scriptFailure()
        let waiting = await waitForReconnectPending(engine, clock, attempt: 1)
        await assertTrue(waiting, engine: engine)
        clock.advance(by: .seconds(1))
        await waitUntil { transport.openCount == 2 }
        let second = try! XCTUnwrap(transport.lastConnection)
        second.scriptOpened()
        let secondSuspended = await waitUntil { second.suspendedSendCount == 1 }
        await assertTrue(secondSuspended, engine: engine)
        await waitUntil { await engine.currentState.isConnected }
        let reconnectsBefore = await engine.metricsSnapshot().reconnectCount

        // Old sender resumes by throwing after the new generation started:
        // it must not report a connection failure for the new generation.
        first.failSuspendedSends()
        await settle()
        let snapshot = await engine.metricsSnapshot()
        XCTAssertTrue(snapshot.connectionState.isConnected, "new generation must stay connected")
        XCTAssertEqual(snapshot.reconnectCount, reconnectsBefore, "stale sender must not schedule a reconnect")
        XCTAssertEqual(transport.openCount, 2)
        let sender = await engine.debugSenderState()
        XCTAssertTrue(sender.hasSenderTask, "new sender remains owned")

        second.resumeSuspendedSends()
        let drained = await waitUntil { second.sentMessages(action: "subscribe").count == 1 }
        await assertTrue(drained, engine: engine)
        await settle()
        XCTAssertEqual(second.sentMessages(action: "subscribe").count, 1, "exact-once replay is intact")
    }

    // MARK: - Stale generation and old-socket suppression

    func testStaleEventsAfterTeardownCannotResurrectConnection() async {
        let (engine, transport, clock) = makeEngine()
        let (consumerID, events) = await engine.register()
        var iterator = events.makeAsyncIterator()
        await engine.replaceSubscriptions(owner: consumerID, with: [tickerBTC])
        let first = try! XCTUnwrap(transport.lastConnection)
        first.scriptOpened()
        first.scriptText(RealtimeFixtureLoader.tickerMessage(price: 100, sequence: 0))

        // Old-socket messages may still be buffered when we disconnect...
        first.scriptText(RealtimeFixtureLoader.tickerMessage(price: 200, sequence: 1))
        await engine.disconnect()
        // ...and a new generation follows.
        await engine.connect()
        let second = try! XCTUnwrap(transport.lastConnection)
        XCTAssertFalse(second === first)
        second.scriptOpened()
        second.scriptText(RealtimeFixtureLoader.tickerMessage(price: 300, sequence: 2))

        // Collect until the new connection's ticker arrives, tracking every
        // ticker seen after the legacy `.disconnected`-equivalent idle state.
        var sawIdleState = false
        var pricesAfterIdle: [Double] = []
        for _ in 0..<10_000 {
            guard let event = await iterator.next() else { break }
            if case .connectionState(.idle) = event {
                sawIdleState = true
            }
            if case .ticker(let payload) = event, sawIdleState {
                pricesAfterIdle.append(payload.ticker.price)
                if payload.ticker.price == 300 { break }
            }
        }

        XCTAssertTrue(sawIdleState)
        let staleDescription = await engineStateDescription(engine)
        XCTAssertEqual(
            pricesAfterIdle,
            [300],
            "no old-socket ticker may be delivered after the idle transition; engine: \(staleDescription)"
        )
        _ = clock
        await engine.unregister(consumerID)
    }

    func testStaleGenerationCallbacksAreCountedAndIgnored() async {
        let (engine, transport, clock) = makeEngine()
        await engine.replaceSubscriptions(owner: UUID(), with: [tickerBTC])
        let first = try! XCTUnwrap(transport.lastConnection)
        first.scriptOpened()
        // Buffer a message, then tear down via the idle policy so the
        // buffered event and stream termination arrive for a dead connection.
        first.scriptText(RealtimeFixtureLoader.tickerMessage(price: 100))
        await engine.replaceSubscriptions(owner: UUID(), with: []) // no-op diff, different owner
        await engine.disconnect()
        await settle()

        clock.advance(by: .seconds(60))
        await settle()
        XCTAssertEqual(transport.openCount, 1, "stale termination must not reconnect")
        let state = await engine.currentState
        XCTAssertEqual(state, .idle)
    }

    // MARK: - Heartbeat

    func testHeartbeatTimeoutTriggersSingleReconnect() async {
        let (engine, transport, clock) = makeEngine()
        await engine.replaceSubscriptions(owner: UUID(), with: [tickerBTC])
        let first = try! XCTUnwrap(transport.lastConnection)
        first.setPingBehavior(.hang)
        first.scriptOpened()

        // Heartbeat sleeps for the ping interval (20s default).
        let heartbeatArmed = await clock.waitForSleepers(atLeast: 1)
        await assertTrue(heartbeatArmed, engine: engine)
        clock.advance(by: .seconds(20))

        // Ping hangs; the pong-timeout sleeper (10s) arms next.
        let pingSent = await waitUntil { first.pingCount == 1 }
        XCTAssertTrue(pingSent)
        await expectSleepers(clock)
        clock.advance(by: .seconds(10))

        // Timeout → one reconnect scheduled (1s backoff).
        await expectSleepers(clock)
        clock.advance(by: .seconds(1))
        let reopened = await waitUntil { transport.openCount == 2 }
        await assertTrue(reopened, engine: engine)

        let snapshot = await engine.metricsSnapshot()
        XCTAssertEqual(snapshot.heartbeatFailureCount, 1)
        XCTAssertEqual(snapshot.reconnectCount, 1)
    }

    func testStaleHeartbeatCallbackIsIgnored() async {
        let (engine, transport, clock) = makeEngine()
        await engine.replaceSubscriptions(owner: UUID(), with: [tickerBTC])
        let connection = try! XCTUnwrap(transport.lastConnection)
        connection.setPingBehavior(.hang)
        connection.scriptOpened()

        await expectSleepers(clock)
        clock.advance(by: .seconds(20))
        await waitUntil { connection.pingCount == 1 }

        // Disconnect while the ping is outstanding: the cancelled ping
        // resolves as a stale heartbeat callback and must change nothing.
        await engine.disconnect()
        await settle()
        clock.advance(by: .seconds(60))
        await settle()

        XCTAssertEqual(transport.openCount, 1, "stale heartbeat must not reconnect")
        XCTAssertEqual(clock.sleeperCount, 0)
        let snapshot = await engine.metricsSnapshot()
        XCTAssertEqual(snapshot.connectionState, .idle)
        XCTAssertEqual(snapshot.heartbeatFailureCount, 0, "cancelled ping is stale, not a heartbeat failure")
    }

    func testHeartbeatSuccessCountsAndResetsBackoff() async {
        let (engine, transport, clock) = makeEngine()
        await engine.replaceSubscriptions(owner: UUID(), with: [tickerBTC])
        let connection = try! XCTUnwrap(transport.lastConnection)
        connection.scriptOpened()

        await expectSleepers(clock)
        clock.advance(by: .seconds(20))
        let success = await waitUntil { await engine.metricsSnapshot().heartbeatSuccessCount >= 1 }
        await assertTrue(
            success,
            engine: engine,
            "sleepers=\(clock.sleeperCount) pings=\(connection.pingCount)"
        )
        let snapshot = await engine.metricsSnapshot()
        XCTAssertEqual(snapshot.heartbeatSuccessCount, 1, "exactly one ping interval elapsed")
        XCTAssertEqual(snapshot.consecutiveReconnectFailures, 0)
    }

    // MARK: - Lifecycle

    func testBackgroundTransitionClosesSocketAndForegroundRestoresSubscriptions() async {
        let (engine, transport, clock) = makeEngine()
        await engine.replaceSubscriptions(owner: UUID(), with: [tickerBTC, tickerETH])
        let first = try! XCTUnwrap(transport.lastConnection)
        first.scriptOpened()
        await waitUntil { first.sentMessages(action: "subscribe").count >= 2 }

        await engine.suspend()
        let closed = await waitUntil { first.isClosed }
        XCTAssertTrue(closed)
        var state = await engine.currentState
        XCTAssertEqual(state, .suspended)
        await settle()
        XCTAssertEqual(clock.sleeperCount, 0, "no reconnect while suspended")

        await engine.resume()
        let reopened = await waitUntil { transport.openCount == 2 }
        XCTAssertTrue(reopened)
        let second = try! XCTUnwrap(transport.lastConnection)
        await waitUntil { second.sentMessages(action: "subscribe").count >= 2 }
        await settle()
        XCTAssertEqual(second.sentMessages(action: "subscribe").count, 2, "subscriptions restored exactly once")
        second.scriptOpened()
        await waitUntil { await engine.currentState.isConnected }
        state = await engine.currentState
        XCTAssertTrue(state.isConnected)
    }

    // MARK: - Event policies through the engine

    func testTickerCoalescingEmitsNewestValueForSlowConsumer() async {
        let (engine, transport, _) = makeEngine()
        let (consumerID, events) = await engine.register()
        var iterator = events.makeAsyncIterator()
        await engine.replaceSubscriptions(owner: consumerID, with: [tickerBTC])
        let connection = try! XCTUnwrap(transport.lastConnection)
        connection.scriptOpened()

        for index in 0..<5 {
            connection.scriptText(RealtimeFixtureLoader.tickerMessage(price: 100 + Double(index), sequence: index))
        }
        await waitUntil { await engine.metricsSnapshot().messagesDecoded == 5 }

        // The consumer never pulled while the burst arrived: all five tickers
        // for the same market collapse to the newest value.
        var tickers: [Double] = []
        for _ in 0..<10 {
            guard let event = await iterator.next() else { break }
            if case .ticker(let payload) = event {
                tickers.append(payload.ticker.price)
            }
            if tickers.count == 1 { break }
        }
        XCTAssertEqual(tickers, [104])
        let snapshot = await engine.metricsSnapshot()
        XCTAssertEqual(snapshot.tickerEventsCoalesced, 4)
        XCTAssertEqual(snapshot.tradeEventsDropped + snapshot.bufferEventsDropped, 0, "coalescing is not dropping")
        await engine.unregister(consumerID)
    }

    func testSeparateMarketsSurviveCoalescingThroughEngine() async {
        let (engine, transport, _) = makeEngine()
        let (consumerID, events) = await engine.register()
        var iterator = events.makeAsyncIterator()
        await engine.replaceSubscriptions(owner: consumerID, with: [tickerBTC, tickerETH])
        let connection = try! XCTUnwrap(transport.lastConnection)
        connection.scriptOpened()

        connection.scriptText(RealtimeFixtureLoader.tickerMessage(symbol: "BTC", price: 100, sequence: 0))
        connection.scriptText(RealtimeFixtureLoader.tickerMessage(symbol: "ETH", price: 10, sequence: 1))
        connection.scriptText(RealtimeFixtureLoader.tickerMessage(symbol: "BTC", price: 101, sequence: 2))
        connection.scriptText(RealtimeFixtureLoader.tickerMessage(symbol: "ETH", price: 11, sequence: 3))
        await waitUntil { await engine.metricsSnapshot().messagesDecoded == 4 }

        var latest: [String: Double] = [:]
        for _ in 0..<10 {
            guard let event = await iterator.next() else { break }
            if case .ticker(let payload) = event {
                latest[payload.symbol] = payload.ticker.price
            }
            if latest.count == 2 { break }
        }
        XCTAssertEqual(latest, ["BTC": 101, "ETH": 11])
        await engine.unregister(consumerID)
    }

    func testMalformedMessagesIncrementMetricsWithoutTerminatingStream() async {
        let (engine, transport, _) = makeEngine()
        let (consumerID, events) = await engine.register()
        var iterator = events.makeAsyncIterator()
        await engine.replaceSubscriptions(owner: consumerID, with: [tickerBTC])
        let connection = try! XCTUnwrap(transport.lastConnection)
        connection.scriptOpened()

        for message in RealtimeFixtureLoader.malformedPayloadStream() {
            connection.scriptText(message)
        }
        let processed = await waitUntil { await engine.metricsSnapshot().transportFramesReceived == 6 }
        await assertTrue(processed, engine: engine)

        // The stream survives: the valid trailing ticker arrives.
        var lastTicker: Double?
        for _ in 0..<20 {
            guard let event = await iterator.next() else { break }
            if case .ticker(let payload) = event {
                lastTicker = payload.ticker.price
                if payload.ticker.price == 102 { break }
            }
        }
        XCTAssertEqual(lastTicker, 102)
        let snapshot = await engine.metricsSnapshot()
        XCTAssertEqual(snapshot.decodeFailures, 4)
        XCTAssertEqual(snapshot.messagesDecoded, 2)
        XCTAssertTrue(snapshot.connectionState.isConnected, "decode failures must not disconnect")
        await engine.unregister(consumerID)
    }

    func testConsumerCancellationTerminatesCleanly() async {
        let (engine, transport, _) = makeEngine()
        let (consumerID, events) = await engine.register()
        await engine.replaceSubscriptions(owner: consumerID, with: [tickerBTC])
        transport.lastConnection?.scriptOpened()

        let consumerTask = Task { () -> Int in
            var count = 0
            for await _ in events {
                count += 1
            }
            return count
        }
        // Let the consumer reach its first suspension, then cancel.
        await settle()
        consumerTask.cancel()
        let consumed = await consumerTask.value
        XCTAssertGreaterThanOrEqual(consumed, 0, "cancellation completes without deadlock")
        await engine.unregister(consumerID)
    }

    func testHundredThousandReplayedTickersCompleteWithoutDeadlock() async {
        let (engine, transport, _) = makeEngine()
        let (consumerID, events) = await engine.register()
        await engine.replaceSubscriptions(owner: consumerID, with: [tickerBTC])
        let connection = try! XCTUnwrap(transport.lastConnection)
        connection.scriptOpened()

        let messages = RealtimeFixtureLoader.multiMarketHighVolumeStream(count: 100_000)

        let consumerTask = Task { () -> Int in
            var emitted = 0
            for await event in events {
                if case .ticker = event {
                    emitted += 1
                }
            }
            return emitted
        }

        for message in messages {
            connection.scriptText(message)
        }

        let drained = await waitUntil(timeout: .seconds(120)) {
            await engine.metricsSnapshot().messagesDecoded == 100_000
        }
        await assertTrue(drained, engine: engine)

        await engine.unregister(consumerID)
        let emitted = await consumerTask.value

        let snapshot = await engine.metricsSnapshot()
        XCTAssertEqual(snapshot.transportFramesReceived, 100_000)
        XCTAssertEqual(snapshot.decodeFailures, 0)
        // Single-consumer delivery conservation: every decoded ticker was
        // delivered to the one consumer, coalesced in its buffer, or counted
        // as an explicit drop — never silently lost. (Valid only because
        // exactly one consumer is registered; with N consumers the
        // delivery-side counters scale by N.)
        XCTAssertEqual(
            emitted + snapshot.tickerEventsCoalesced + snapshot.tradeEventsDropped + snapshot.bufferEventsDropped
                + snapshot.staleIdentityEventsDropped,
            100_000,
            "every ticker is delivered, coalesced, or explicitly dropped — never silently lost"
        )
        XCTAssertLessThanOrEqual(snapshot.maxBufferUsage, 1024)
    }

    // MARK: - Legacy fixture streams

    func testDuplicateAndOutOfOrderStreamsDecodeDeterministically() async {
        let (engine, transport, _) = makeEngine()
        await engine.replaceSubscriptions(owner: UUID(), with: [tickerBTC])
        let connection = try! XCTUnwrap(transport.lastConnection)
        connection.scriptOpened()

        for message in RealtimeFixtureLoader.duplicateTickerStream(count: 10) {
            connection.scriptText(message)
        }
        for message in RealtimeFixtureLoader.outOfOrderTickerStream(count: 10) {
            connection.scriptText(message)
        }
        let done = await waitUntil { await engine.metricsSnapshot().messagesDecoded == 30 }
        await assertTrue(done, engine: engine)
        let snapshot = await engine.metricsSnapshot()
        XCTAssertEqual(snapshot.decodeFailures, 0)
    }
}
