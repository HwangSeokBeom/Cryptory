import XCTest
@testable import Cryptory

/// Deterministic tests for the pull-based transport ingress contract: no
/// unbounded raw-frame queue may form between the socket and the engine's
/// decoder. The scripted queue models the network side; the app-side
/// transport hands over at most one frame per outstanding `receive()`.
final class RealtimeTransportTests: XCTestCase {
    private let tickerBTC = PublicMarketSubscription(channel: .ticker, exchange: "upbit", symbol: "BTC")

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

    func testEngineKeepsExactlyOneReceiveOutstanding() async {
        let (engine, transport, _) = makeEngine()
        await engine.replaceSubscriptions(owner: UUID(), with: [tickerBTC])
        let connection = try! XCTUnwrap(transport.lastConnection)
        connection.scriptOpened()
        for index in 0..<100 {
            connection.scriptText(RealtimeFixtureLoader.tickerMessage(price: 100 + Double(index), sequence: index))
        }
        let drained = await waitUntil { await engine.metricsSnapshot().messagesDecoded == 100 }
        let snapshot = await engine.metricsSnapshot()
        XCTAssertTrue(drained, "engine must pull all frames; decoded=\(snapshot.messagesDecoded)")
        XCTAssertEqual(connection.maxConcurrentReceiveWaiters, 1, "at most one receive may be outstanding")
        XCTAssertEqual(connection.pendingScriptedEventCount, 0, "network-side backlog drains")
        // Reconciliation: every delivered frame is either the .opened control
        // event or a message counted by the engine — nothing is lost or
        // duplicated between the transport and the decoder.
        XCTAssertEqual(connection.deliveredFrameCount, snapshot.messagesReceived + 1)
    }

    func testProducerFasterThanDecoderNeverBuildsAppSideQueue() async {
        let (engine, transport, _) = makeEngine()
        let (consumerID, _) = await engine.register()
        await engine.replaceSubscriptions(owner: consumerID, with: [tickerBTC])
        let connection = try! XCTUnwrap(transport.lastConnection)
        connection.scriptOpened()

        // Producer bursts 10k frames with no consumer pulling the engine
        // stream: the backlog must remain on the modeled network side and the
        // transport must still hand over only one frame per engine request.
        let messages = RealtimeFixtureLoader.multiMarketHighVolumeStream(count: 10_000)
        for message in messages {
            connection.scriptText(message)
        }
        let drained = await waitUntil { await engine.metricsSnapshot().messagesDecoded == 10_000 }
        let snapshot = await engine.metricsSnapshot()
        XCTAssertTrue(drained, "decoded=\(snapshot.messagesDecoded)")
        XCTAssertEqual(connection.maxConcurrentReceiveWaiters, 1, "configured transport bound (1 frame) never exceeded")
        XCTAssertEqual(snapshot.decodeFailures, 0, "no raw frame is silently discarded")
        XCTAssertEqual(connection.deliveredFrameCount, snapshot.messagesReceived + 1)
        await engine.unregister(consumerID)
    }

    func testCancellationTerminatesPendingReceive() async {
        let transport = ScriptedWebSocketTransport()
        _ = transport.open(url: URL(string: "wss://unit.test/ws/market")!)
        let connection = try! XCTUnwrap(transport.lastConnection)

        let receiveTask = Task<Error?, Never> {
            do {
                _ = try await connection.receive()
                return nil
            } catch {
                return error
            }
        }
        let waiting = await waitUntil { connection.hasPendingReceiveWaiter }
        XCTAssertTrue(waiting, "receive must suspend with no scripted events")

        receiveTask.cancel()
        let error = await receiveTask.value
        XCTAssertTrue(error is CancellationError, "cancellation must terminate the pending receive, got \(String(describing: error))")
        XCTAssertFalse(connection.hasPendingReceiveWaiter)
    }

    func testCloseTerminatesPendingReceiveAndNoLoopSurvivesDisconnect() async {
        let (engine, transport, _) = makeEngine()
        await engine.replaceSubscriptions(owner: UUID(), with: [tickerBTC])
        let connection = try! XCTUnwrap(transport.lastConnection)
        connection.scriptOpened()
        await waitUntil { connection.sentMessages(action: "subscribe").count >= 1 }
        let looping = await waitUntil { connection.hasPendingReceiveWaiter }
        XCTAssertTrue(looping, "receive loop is pulling")

        await engine.disconnect()
        let loopGone = await waitUntil { !connection.hasPendingReceiveWaiter }
        XCTAssertTrue(loopGone, "no receive loop may survive disconnect")
        XCTAssertTrue(connection.isClosed)

        // Frames scripted after disconnect are never pulled into the engine.
        let receivedBefore = await engine.metricsSnapshot().messagesReceived
        connection.scriptText(RealtimeFixtureLoader.tickerMessage(price: 999))
        await settle()
        let receivedAfter = await engine.metricsSnapshot().messagesReceived
        XCTAssertEqual(receivedAfter, receivedBefore, "dead connection frames must not reach the decoder")
        XCTAssertFalse(connection.hasPendingReceiveWaiter)
    }

    func testHundredThousandMessageReplayHoldsPullContract() async {
        let (engine, transport, _) = makeEngine()
        let (consumerID, events) = await engine.register()
        await engine.replaceSubscriptions(owner: consumerID, with: [tickerBTC])
        let connection = try! XCTUnwrap(transport.lastConnection)
        connection.scriptOpened()

        let consumerTask = Task { () -> Int in
            var emitted = 0
            for await event in events {
                if case .ticker = event {
                    emitted += 1
                }
            }
            return emitted
        }

        for message in RealtimeFixtureLoader.multiMarketHighVolumeStream(count: 100_000) {
            connection.scriptText(message)
        }
        let drained = await waitUntil(timeout: .seconds(120)) {
            await engine.metricsSnapshot().messagesDecoded == 100_000
        }
        let snapshot = await engine.metricsSnapshot()
        XCTAssertTrue(drained, "decoded=\(snapshot.messagesDecoded)")
        XCTAssertEqual(connection.maxConcurrentReceiveWaiters, 1, "100k replay must not rely on an unbounded stream")
        XCTAssertEqual(connection.pendingScriptedEventCount, 0)
        XCTAssertEqual(connection.deliveredFrameCount, snapshot.messagesReceived + 1)
        await engine.unregister(consumerID)
        _ = await consumerTask.value
    }
}
