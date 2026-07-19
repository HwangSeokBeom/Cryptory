import XCTest
@testable import Cryptory

/// Reproducible replay benchmark for the realtime pipeline.
///
/// Uses the scripted transport (no network) and the real continuous clock so
/// elapsed time is wall-clock. Results are printed as structured
/// `REALTIME_BENCHMARK` lines; measured values are recorded in
/// Docs/PERFORMANCE_BASELINE.md. Assertions only check completeness, not
/// timing, so the test never fails on slower machines.
final class RealtimeReplayBenchmarkTests: XCTestCase {
    private let tickerBTC = PublicMarketSubscription(channel: .ticker, exchange: "upbit", symbol: "BTC")

    func testReplayThroughputHundredThousandMessages() async throws {
        let messageCount = 100_000
        let transport = ScriptedWebSocketTransport()
        let engine = MarketStreamEngine(
            url: URL(string: "wss://bench.test/ws/market")!,
            transport: transport,
            clock: ContinuousRealtimeClock(),
            jitter: { 0.5 }
        )
        let (consumerID, events) = await engine.register()
        await engine.replaceSubscriptions(owner: consumerID, with: [tickerBTC])
        let connection = try XCTUnwrap(transport.lastConnection)
        connection.scriptOpened()

        let messages = RealtimeFixtureLoader.multiMarketHighVolumeStream(count: messageCount)

        let consumerTask = Task { () -> Int in
            var emitted = 0
            for await event in events {
                if case .ticker = event {
                    emitted += 1
                }
            }
            return emitted
        }

        let clock = ContinuousClock()
        let start = clock.now
        for message in messages {
            connection.scriptText(message)
        }
        let feedDone = clock.now

        var yields = 0
        while await engine.metricsSnapshot().messagesDecoded < messageCount {
            yields += 1
            if yields > 20_000_000 {
                return XCTFail("replay did not drain: \(await engine.metricsSnapshot())")
            }
            await Task.yield()
        }
        let drainDone = clock.now

        await engine.unregister(consumerID)
        let emitted = await consumerTask.value
        let snapshot = await engine.metricsSnapshot()

        let elapsed = start.duration(to: drainDone).asSeconds
        let feedElapsed = start.duration(to: feedDone).asSeconds
        let throughput = Double(messageCount) / elapsed

        print("""
        REALTIME_BENCHMARK replay \
        messages=\(messageCount) \
        elapsed_s=\(String(format: "%.3f", elapsed)) \
        feed_s=\(String(format: "%.3f", feedElapsed)) \
        throughput_msgs_per_s=\(String(format: "%.0f", throughput)) \
        decoded=\(snapshot.messagesDecoded) \
        emitted=\(emitted) \
        coalesced=\(snapshot.tickerEventsCoalesced) \
        dropped=\(snapshot.tradeEventsDropped + snapshot.bufferEventsDropped) \
        decode_failures=\(snapshot.decodeFailures) \
        reconnects=\(snapshot.reconnectCount) \
        max_buffer=\(snapshot.maxBufferUsage) \
        latency_p50_ms=\(snapshot.latencyP50.map { String(format: "%.2f", $0 * 1000) } ?? "n/a") \
        latency_p95_ms=\(snapshot.latencyP95.map { String(format: "%.2f", $0 * 1000) } ?? "n/a")
        """)

        XCTAssertEqual(snapshot.transportFramesReceived, messageCount)
        XCTAssertEqual(snapshot.messagesDecoded, messageCount)
        XCTAssertEqual(snapshot.decodeFailures, 0)
        // Single-consumer delivery conservation (valid because exactly one
        // consumer is registered in this benchmark).
        XCTAssertEqual(
            emitted + snapshot.tickerEventsCoalesced + snapshot.tradeEventsDropped + snapshot.bufferEventsDropped,
            messageCount,
            "conservation: every ticker delivered, coalesced, or counted as dropped"
        )
    }

    func testFirstMarketEventDeliveryLatency() async throws {
        let transport = ScriptedWebSocketTransport()
        let engine = MarketStreamEngine(
            url: URL(string: "wss://bench.test/ws/market")!,
            transport: transport,
            clock: ContinuousRealtimeClock(),
            jitter: { 0.5 }
        )
        let (consumerID, events) = await engine.register()
        var iterator = events.makeAsyncIterator()
        await engine.replaceSubscriptions(owner: consumerID, with: [tickerBTC])
        let connection = try XCTUnwrap(transport.lastConnection)
        connection.scriptOpened()

        let clock = ContinuousClock()
        let start = clock.now
        connection.scriptText(RealtimeFixtureLoader.tickerMessage(price: 100))

        var firstTickerLatency: Double?
        for _ in 0..<100 {
            guard let event = await iterator.next() else { break }
            if case .ticker = event {
                firstTickerLatency = start.duration(to: clock.now).asSeconds
                break
            }
        }

        let latency = try XCTUnwrap(firstTickerLatency, "first ticker must arrive")
        print("REALTIME_BENCHMARK first_event latency_ms=\(String(format: "%.3f", latency * 1000))")
        await engine.unregister(consumerID)
    }
}
