import Foundation
import OSLog

/// Actor-isolated public market stream engine.
///
/// Sole owner of: connection state, socket generation, reconnect attempt
/// count, subscription registry, heartbeat state, event buffers, metrics.
/// Consumers receive events through `AsyncStream<MarketStreamEvent>`; the
/// transport is abstract (`WebSocketTransport`) and never touches UI state.
///
/// Design, policies, and rationale: Docs/REALTIME_PIPELINE.md and
/// Docs/ADR/0001-actor-isolated-realtime-engine.md.
actor MarketStreamEngine {
    // MARK: - Configuration

    private let url: URL
    private let transport: any WebSocketTransport
    private let clock: any RealtimeClock
    private let reconnectPolicy: ReconnectPolicy
    private let heartbeatPolicy: HeartbeatPolicy
    private let bufferCapacity: Int
    private let maxTradeBatchesPerMarket: Int
    private let jitter: @Sendable () -> Double

    // MARK: - Actor-owned state

    private var generation: UInt64 = 0
    private var state: MarketStreamConnectionState = .idle
    private var connection: (any WebSocketTransportConnection)?
    private var receiveTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var senderTask: Task<Void, Never>?
    /// Ownership token for the current sender task. Incremented whenever a
    /// sender is created or the connection is torn down, so a stale sender
    /// resuming from a suspended `send(text:)` after teardown can never
    /// mutate the state of a newer sender or connection (URLSession and test
    /// doubles may resume a send even after cancellation).
    private var senderEpoch: UInt64 = 0
    private var outbox: [String] = []
    private var closeWhenOutboxDrained = false

    private var registry = MarketSubscriptionRegistry()
    private var reconnectAttempts = 0
    private var connectionProvenUseful = false
    private var pingWaiter: CheckedContinuation<Bool, Never>?
    private var pingEpoch: UInt64 = 0
    private var pingTask: Task<Void, Never>?
    private var pingTimeoutTask: Task<Void, Never>?
    private var suspended = false
    private var manuallyDisconnected = false
    private var connectedAt: Duration?

    private var consumers: [UUID: Consumer] = [:]
    private var metrics = RealtimeMetrics()

    private struct Consumer {
        var buffer = MarketStreamEventBuffer()
        var waiter: CheckedContinuation<MarketStreamEvent?, Never>?
    }

    // MARK: - Init

    init(
        url: URL,
        transport: any WebSocketTransport,
        clock: any RealtimeClock = ContinuousRealtimeClock(),
        reconnectPolicy: ReconnectPolicy = ReconnectPolicy(),
        heartbeatPolicy: HeartbeatPolicy = HeartbeatPolicy(),
        bufferCapacity: Int = 1024,
        maxTradeBatchesPerMarket: Int = 64,
        jitter: @escaping @Sendable () -> Double = { Double.random(in: 0..<1) }
    ) {
        self.url = url
        self.transport = transport
        self.clock = clock
        self.reconnectPolicy = reconnectPolicy
        self.heartbeatPolicy = heartbeatPolicy
        self.bufferCapacity = bufferCapacity
        self.maxTradeBatchesPerMarket = maxTradeBatchesPerMarket
        self.jitter = jitter
    }

    // MARK: - Consumer API

    /// Registers a consumer and returns its event stream. The stream ends
    /// when the consumer task is cancelled or `unregister(_:)` is called.
    func register() -> (id: UUID, events: AsyncStream<MarketStreamEvent>) {
        let id = UUID()
        consumers[id] = Consumer()
        let stream = AsyncStream<MarketStreamEvent>(unfolding: { [weak self] in
            await self?.next(for: id)
        })
        return (id, stream)
    }

    /// Removes a consumer: ends its stream and releases its subscriptions.
    func unregister(_ id: UUID) {
        guard var consumer = consumers.removeValue(forKey: id) else { return }
        // Pending events discarded with the consumer are explicit drops —
        // the conservation invariant (decoded == emitted + coalesced +
        // dropped) must hold at every point; nothing is lost silently.
        if consumer.buffer.count > 0 {
            metrics.recordEventsDropped(consumer.buffer.count)
        }
        consumer.waiter?.resume(returning: nil)
        consumer.waiter = nil
        let unsubscribed = registry.removeOwner(id)
        applyRegistryChange(
            diff: MarketSubscriptionRegistry.Diff(subscribe: [], unsubscribe: unsubscribed)
        )
    }

    /// Replaces the full subscription set owned by `owner`. Reference counting
    /// ensures one upstream subscribe per distinct subscription and one
    /// unsubscribe when its last owner leaves. Rapid replacement converges to
    /// the final set.
    func replaceSubscriptions(owner: UUID, with subscriptions: Set<PublicMarketSubscription>) {
        let diff = registry.replace(owner: owner, with: subscriptions)
        if !subscriptions.isEmpty {
            // Parity with the legacy service: a non-empty subscription update
            // revives the stream after a manual disconnect.
            manuallyDisconnected = false
        }
        applyRegistryChange(diff: diff)
    }

    /// Idempotent. Opens a connection when at least one subscription is
    /// active; with zero subscriptions the engine stays idle by policy.
    ///
    /// Documented bypass: an explicit `connect()` while the engine is in
    /// `waitingToReconnect` cancels the scheduled backoff timer and connects
    /// immediately — it is a deliberate user/caller action, unlike
    /// subscription reconciliation, which never bypasses the wait.
    func connect() {
        manuallyDisconnected = false
        guard connection == nil else { return }
        startConnectionIfNeeded()
    }

    /// Idempotent. Closes the connection, cancels reconnect and heartbeat,
    /// and suppresses reconnects until `connect()` or a non-empty
    /// subscription update.
    func disconnect() {
        manuallyDisconnected = true
        cancelReconnect()
        reconnectAttempts = 0
        guard connection != nil || state != .idle else { return }
        teardownConnection()
        metrics.recordDisconnect(reason: MarketStreamDisconnectReason.manual.description)
        setState(.idle)
    }

    // MARK: - Lifecycle API

    /// App moved to the background: close the socket, keep the registry so
    /// the foreground transition can restore subscriptions.
    func suspend() {
        guard !suspended else { return }
        suspended = true
        cancelReconnect()
        if connection != nil {
            teardownConnection()
            metrics.recordDisconnect(reason: MarketStreamDisconnectReason.background.description)
        }
        setState(.suspended)
    }

    /// App returned to the foreground: reconnect and replay subscriptions if
    /// any consumer still owns them.
    func resume() {
        guard suspended else { return }
        suspended = false
        if !manuallyDisconnected, !registry.isEmpty {
            startConnectionIfNeeded()
        } else {
            setState(.idle)
        }
    }

    // MARK: - Introspection

    func metricsSnapshot() -> RealtimeMetricsSnapshot {
        var snapshot = RealtimeMetricsSnapshot()
        snapshot.connectionState = state
        snapshot.generation = generation
        snapshot.connectedAt = connectedAt
        snapshot.uptime = connectedAt.map { clock.now - $0 } ?? .zero
        snapshot.activeSubscriptionCount = registry.totalOwnershipCount
        snapshot.upstreamSubscriptionCount = registry.subscriptionCount
        snapshot.messagesReceived = metrics.messagesReceived
        snapshot.messagesDecoded = metrics.messagesDecoded
        snapshot.decodeFailures = metrics.decodeFailures
        snapshot.messagesEmitted = metrics.messagesEmitted
        snapshot.tickersCoalesced = metrics.tickersCoalesced
        snapshot.eventsDropped = metrics.eventsDropped
        snapshot.staleEventsIgnored = metrics.staleEventsIgnored
        snapshot.reconnectCount = metrics.reconnectCount
        snapshot.consecutiveReconnectFailures = metrics.consecutiveReconnectFailures
        snapshot.lastDisconnectReason = metrics.lastDisconnectReason
        snapshot.heartbeatSuccessCount = metrics.heartbeatSuccessCount
        snapshot.heartbeatFailureCount = metrics.heartbeatFailureCount
        snapshot.latestEventLatency = metrics.latestEventLatency
        let percentiles = metrics.latencyPercentiles()
        snapshot.latencyP50 = percentiles.p50
        snapshot.latencyP95 = percentiles.p95
        snapshot.maxBufferUsage = metrics.maxBufferUsage
        return snapshot
    }

    var currentState: MarketStreamConnectionState { state }
    var activeSubscriptions: Set<PublicMarketSubscription> { registry.activeSubscriptions }

    // MARK: - Subscription reconciliation

    private func applyRegistryChange(diff: MarketSubscriptionRegistry.Diff) {
        if registry.isEmpty {
            // Zero subscriptions: no socket is kept alive. Flush pending
            // unsubscribes, then close (legacy parity: empty set tears down).
            cancelReconnect()
            reconnectAttempts = 0
            if connection != nil {
                enqueueSubscriptionMessages(unsubscribe: diff.unsubscribe, subscribe: [])
                closeWhenOutboxDrained = true
                if senderTask == nil {
                    finishIdleCloseIfNeeded()
                }
            } else if state != .idle, state != .suspended {
                setState(.idle)
            }
            return
        }

        // The registry is non-empty again: any pending idle-close intent is
        // obsolete — the socket must stay alive for the current subscriptions
        // (A → [] → B during a suspended send must not close B's connection).
        closeWhenOutboxDrained = false

        if connection == nil {
            // While waiting to reconnect, only reconcile the registry: the
            // scheduled timer replays the full active set exactly once when
            // it fires. Subscription churn (e.g. repeated UI refreshes
            // during an outage) must never cancel or reset backoff; only the
            // timer itself or an explicit `connect()` bypasses the wait.
            if case .waitingToReconnect = state { return }
            if !suspended, !manuallyDisconnected {
                startConnectionIfNeeded()
            }
            return
        }

        enqueueSubscriptionMessages(unsubscribe: diff.unsubscribe, subscribe: diff.subscribe)
        if !diff.isEmpty {
            RealtimeLog.subscription.debug(
                "reconcile gen=\(self.generation, privacy: .public) +\(diff.subscribe.count, privacy: .public) -\(diff.unsubscribe.count, privacy: .public) upstream=\(self.registry.subscriptionCount, privacy: .public)"
            )
        }
    }

    private func enqueueSubscriptionMessages(
        unsubscribe: Set<PublicMarketSubscription>,
        subscribe: Set<PublicMarketSubscription>
    ) {
        guard let connection else { return }
        for subscription in unsubscribe {
            outbox.append(MarketStreamDecoder.subscriptionMessage(for: subscription, action: "unsubscribe"))
        }
        for subscription in subscribe {
            outbox.append(MarketStreamDecoder.subscriptionMessage(for: subscription, action: "subscribe"))
        }
        ensureSender(connection, generation: generation)
    }

    // MARK: - Connection lifecycle

    private func startConnectionIfNeeded() {
        guard connection == nil, !suspended, !manuallyDisconnected, !registry.isEmpty else { return }
        cancelReconnect()

        generation += 1
        let gen = generation
        connectionProvenUseful = false
        closeWhenOutboxDrained = false
        setState(.connecting(generation: gen))
        RealtimeLog.connection.info("connect gen=\(gen, privacy: .public)")

        let newConnection = transport.open(url: url)
        connection = newConnection

        // Replay the active subscription set exactly once per generation.
        outbox = registry.activeSubscriptions.map {
            MarketStreamDecoder.subscriptionMessage(for: $0, action: "subscribe")
        }
        ensureSender(newConnection, generation: gen)

        receiveTask = Task { await self.runReceiveLoop(newConnection, generation: gen) }
    }

    private func teardownConnection() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
        resolvePing(epoch: pingEpoch, result: false)
        senderTask?.cancel()
        senderTask = nil
        // Invalidate any sender still suspended inside `send(text:)`: when it
        // eventually resumes (even ignoring cancellation) its epoch no longer
        // matches and it exits without touching newer state.
        senderEpoch &+= 1
        outbox = []
        closeWhenOutboxDrained = false
        receiveTask = nil
        connectedAt = nil
        connectionProvenUseful = false
        if let connection {
            connection.close()
        }
        connection = nil
    }

    private func cancelReconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
    }

    private func runReceiveLoop(
        _ connection: any WebSocketTransportConnection,
        generation gen: UInt64
    ) async {
        do {
            for try await event in connection.events {
                // Generation must match AND a live connection must exist:
                // a manual disconnect tears the connection down without
                // bumping the generation, and buffered events from the old
                // socket must not be processed after that.
                guard gen == generation, self.connection != nil else {
                    metrics.recordStaleEventIgnored()
                    return
                }
                switch event {
                case .opened:
                    handleOpened(generation: gen)
                case .text(let text):
                    handleText(text, generation: gen)
                case .closed(let code, _):
                    handleConnectionFailure(generation: gen, reason: .connectionClosed(code: code))
                    return
                }
            }
            guard gen == generation, self.connection != nil else { return }
            handleConnectionFailure(generation: gen, reason: .connectionClosed(code: nil))
        } catch {
            guard gen == generation, self.connection != nil else {
                metrics.recordStaleEventIgnored()
                return
            }
            handleConnectionFailure(
                generation: gen,
                reason: .transportError(Self.shortDescription(of: error))
            )
        }
    }

    private func handleOpened(generation gen: UInt64) {
        guard gen == generation, connection != nil else {
            metrics.recordStaleEventIgnored()
            return
        }
        connectedAt = clock.now
        setState(.connected(generation: gen))
        RealtimeLog.connection.info("connected gen=\(gen, privacy: .public)")
        startHeartbeat(generation: gen)
        // Note: backoff is NOT reset here. The connection must prove useful
        // first (first decoded market event or heartbeat pong).
    }

    private func handleText(_ text: String, generation gen: UInt64) {
        guard gen == generation, connection != nil else {
            metrics.recordStaleEventIgnored()
            return
        }
        metrics.recordMessageReceived()

        switch MarketStreamDecoder.decode(text) {
        case .event(let parsed):
            metrics.recordMessageDecoded()
            markConnectionUseful(generation: gen)
            dispatch(Self.streamEvent(for: parsed))
        case .control:
            break
        case .failure:
            // Malformed messages increment metrics but never terminate the
            // stream or the connection.
            metrics.recordDecodeFailure()
        }
    }

    private func handleConnectionFailure(generation gen: UInt64, reason: MarketStreamDisconnectReason) {
        guard gen == generation, connection != nil else {
            metrics.recordStaleEventIgnored()
            return
        }
        teardownConnection()
        metrics.recordDisconnect(reason: reason.description)
        RealtimeLog.connection.info(
            "disconnected gen=\(gen, privacy: .public) reason=\(reason.description, privacy: .public)"
        )

        if manuallyDisconnected {
            setState(.idle)
            return
        }
        if suspended {
            setState(.suspended)
            return
        }
        if registry.isEmpty {
            setState(.idle)
            return
        }
        scheduleReconnect(generation: gen, reason: reason)
    }

    private func scheduleReconnect(generation gen: UInt64, reason: MarketStreamDisconnectReason) {
        reconnectAttempts += 1
        let attempt = reconnectAttempts
        let delay = reconnectPolicy.delay(forAttempt: attempt, jitterUnit: jitter())
        metrics.recordReconnectScheduled(reason: reason.description)
        setState(.waitingToReconnect(generation: gen, attempt: attempt, reason: reason.description))
        RealtimeLog.connection.info(
            "reconnect scheduled attempt=\(attempt, privacy: .public) delay=\(String(describing: delay), privacy: .public)"
        )

        reconnectTask = Task {
            do {
                try await self.clock.sleep(for: delay)
            } catch {
                return
            }
            self.reconnectTimerFired(expectedGeneration: gen)
        }
    }

    private func reconnectTimerFired(expectedGeneration: UInt64) {
        // A stale reconnect timer (older generation, or superseded by manual
        // disconnect / suspension / idle teardown) must do nothing.
        guard expectedGeneration == generation else {
            metrics.recordStaleEventIgnored()
            return
        }
        guard case .waitingToReconnect = state else { return }
        guard !manuallyDisconnected, !suspended, !registry.isEmpty else { return }
        startConnectionIfNeeded()
    }

    /// Resets backoff once the connection has proven useful (documented
    /// stability condition: first decoded market event or heartbeat pong).
    private func markConnectionUseful(generation gen: UInt64) {
        guard gen == generation, !connectionProvenUseful else { return }
        connectionProvenUseful = true
        reconnectAttempts = 0
        metrics.recordConnectionStable()
        RealtimeLog.connection.debug("connection stable gen=\(gen, privacy: .public)")
    }

    // MARK: - Heartbeat

    private func startHeartbeat(generation gen: UInt64) {
        heartbeatTask?.cancel()
        heartbeatTask = Task { await self.runHeartbeat(generation: gen) }
    }

    private func runHeartbeat(generation gen: UInt64) async {
        while !Task.isCancelled, gen == generation, let connection {
            do {
                try await clock.sleep(for: heartbeatPolicy.pingInterval)
            } catch {
                return
            }
            guard gen == generation, self.connection != nil else {
                metrics.recordStaleEventIgnored()
                return
            }

            let pongReceived = await awaitPingResult(on: connection)

            // A pong (or timeout) that races a generation change is stale and
            // must not touch state.
            guard gen == generation, self.connection != nil else {
                metrics.recordStaleEventIgnored()
                return
            }

            if pongReceived {
                metrics.recordHeartbeatSuccess()
                markConnectionUseful(generation: gen)
            } else {
                metrics.recordHeartbeatFailure()
                RealtimeLog.heartbeat.info("heartbeat timeout gen=\(gen, privacy: .public)")
                handleConnectionFailure(generation: gen, reason: .heartbeatTimeout)
                return
            }
        }
    }

    /// Races the transport ping against the pong timeout.
    ///
    /// Implemented with an explicit continuation resolved by two plain
    /// actor-inherited tasks (first resolution wins; the loser is cancelled).
    /// A `withTaskGroup` implementation intermittently hung here: with
    /// actor-inherited children, `group.next()` sometimes never delivered the
    /// completed ping child (observed under full-suite load: ping sent,
    /// timeout child suspended, parent stuck 30s). The continuation pattern
    /// matches the engine's other timers and is deterministic under the
    /// manual test clock.
    private func awaitPingResult(on connection: any WebSocketTransportConnection) async -> Bool {
        pingEpoch &+= 1
        let epoch = pingEpoch
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            pingWaiter = continuation
            pingTask = Task {
                let pongReceived = (try? await connection.sendPing()) != nil
                self.resolvePing(epoch: epoch, result: pongReceived)
            }
            pingTimeoutTask = Task {
                try? await self.clock.sleep(for: self.heartbeatPolicy.pongTimeout)
                self.resolvePing(epoch: epoch, result: false)
            }
        }
    }

    /// First resolution for the current epoch wins; stale resolutions are
    /// no-ops. Cancels the losing task so no timer outlives the ping.
    private func resolvePing(epoch: UInt64, result: Bool) {
        guard epoch == pingEpoch, let waiter = pingWaiter else { return }
        pingWaiter = nil
        pingTask?.cancel()
        pingTask = nil
        pingTimeoutTask?.cancel()
        pingTimeoutTask = nil
        waiter.resume(returning: result)
    }

    // MARK: - Outbound sends

    private func ensureSender(_ connection: any WebSocketTransportConnection, generation gen: UInt64) {
        guard senderTask == nil else { return }
        senderEpoch &+= 1
        let epoch = senderEpoch
        senderTask = Task { await self.drainOutbox(connection, generation: gen, senderEpoch: epoch) }
    }

    /// Drains the outbox for exactly one sender epoch. Every shared-state
    /// mutation is guarded by the epoch (and generation) captured at spawn:
    /// a stale sender resuming from a suspended send after teardown must not
    /// clear a newer `senderTask`, drain a newer outbox, trigger idle close,
    /// or schedule a reconnect for a newer generation.
    private func drainOutbox(
        _ connection: any WebSocketTransportConnection,
        generation gen: UInt64,
        senderEpoch epoch: UInt64
    ) async {
        while epoch == senderEpoch, gen == generation, !outbox.isEmpty, !Task.isCancelled {
            let message = outbox.removeFirst()
            do {
                try await connection.send(text: message)
            } catch {
                guard epoch == senderEpoch, gen == generation else { return }
                senderTask = nil
                handleConnectionFailure(
                    generation: gen,
                    reason: .transportError(Self.shortDescription(of: error))
                )
                return
            }
        }
        guard epoch == senderEpoch else { return }
        senderTask = nil
        guard gen == generation else { return }
        finishIdleCloseIfNeeded()
    }

    private func finishIdleCloseIfNeeded() {
        guard closeWhenOutboxDrained else { return }
        closeWhenOutboxDrained = false
        teardownConnection()
        metrics.recordDisconnect(reason: MarketStreamDisconnectReason.idle.description)
        setState(.idle)
    }

    // MARK: - Event dispatch

    private func setState(_ newState: MarketStreamConnectionState) {
        guard state != newState else { return }
        state = newState
        dispatch(.connectionState(newState))
    }

    private func dispatch(_ event: MarketStreamEvent) {
        guard !consumers.isEmpty else { return }
        let now = clock.now
        for (id, var consumer) in consumers {
            if let waiter = consumer.waiter {
                consumer.waiter = nil
                consumers[id] = consumer
                metrics.recordEmission(latency: 0)
                waiter.resume(returning: event)
                continue
            }
            let result = consumer.buffer.enqueue(
                event,
                at: now,
                capacity: bufferCapacity,
                maxTradeBatchesPerMarket: maxTradeBatchesPerMarket
            )
            consumers[id] = consumer
            if result.coalescedTicker {
                metrics.recordTickerCoalesced()
            }
            if result.droppedEvents > 0 {
                metrics.recordEventsDropped(result.droppedEvents)
            }
            metrics.recordBufferUsage(consumer.buffer.count)
        }
    }

    private func next(for id: UUID) async -> MarketStreamEvent? {
        guard consumers[id] != nil else { return nil }
        if Task.isCancelled {
            unregister(id)
            return nil
        }
        if var consumer = consumers[id], let queued = consumer.buffer.dequeue() {
            consumers[id] = consumer
            let latency = (clock.now - queued.enqueuedAt).asSeconds
            metrics.recordEmission(latency: latency)
            return queued.event
        }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<MarketStreamEvent?, Never>) in
                guard var consumer = consumers[id] else {
                    continuation.resume(returning: nil)
                    return
                }
                // A second concurrent waiter for the same consumer is a
                // programming error; end the older one deterministically.
                consumer.waiter?.resume(returning: nil)
                consumer.waiter = continuation
                consumers[id] = consumer
            }
        } onCancel: {
            Task { await self.cancelWaiter(for: id) }
        }
    }

    private func cancelWaiter(for id: UUID) {
        guard var consumer = consumers[id], let waiter = consumer.waiter else { return }
        consumer.waiter = nil
        consumers[id] = consumer
        waiter.resume(returning: nil)
    }

    // MARK: - Helpers

    private static func streamEvent(for parsed: MarketWebSocketParsedMessage) -> MarketStreamEvent {
        switch parsed {
        case .ticker(let payload):
            return .ticker(payload)
        case .orderbook(let payload):
            return .orderbook(payload)
        case .trades(let payload):
            return .trades(payload)
        case .candles(let payload):
            return .candles(payload)
        }
    }

    private static func shortDescription(of error: Error) -> String {
        let nsError = error as NSError
        return "\(nsError.domain)(\(nsError.code))"
    }
}

#if DEBUG
// Test/diagnostic introspection. DEBUG-only; read-only snapshots of
// actor-owned state for deterministic assertions.
extension MarketStreamEngine {
    struct DebugSenderState: Sendable, Equatable {
        var hasSenderTask: Bool
        var senderEpoch: UInt64
        var outboxCount: Int
        var closeWhenOutboxDrained: Bool
    }

    func debugSenderState() -> DebugSenderState {
        DebugSenderState(
            hasSenderTask: senderTask != nil,
            senderEpoch: senderEpoch,
            outboxCount: outbox.count,
            closeWhenOutboxDrained: closeWhenOutboxDrained
        )
    }

    var debugConsumerCount: Int { consumers.count }
}

// Simulation hooks for the Realtime Pipeline Lab. DEBUG-only: they act on
// this local engine instance and cannot reach production users, credentials,
// or other devices. Not compiled into Release builds.
extension MarketStreamEngine {
    /// Closes the live transport as if the network dropped; exercises the
    /// real failure → backoff → reconnect path.
    func debugSimulateConnectionFailure() {
        connection?.close()
    }

    /// Injects a heartbeat timeout for the current generation.
    func debugSimulateHeartbeatTimeout() {
        guard connection != nil else { return }
        metrics.recordHeartbeatFailure()
        handleConnectionFailure(generation: generation, reason: .heartbeatTimeout)
    }

    /// Churns a scratch owner through several subscription sets, ending with
    /// none — refcounting must leave real consumers' subscriptions intact.
    func debugSimulateRapidSubscriptionReplacement() {
        let owner = UUID()
        let scratch = PublicMarketSubscription(channel: .ticker, exchange: "debuglab", symbol: "LAB")
        let scratch2 = PublicMarketSubscription(channel: .trades, exchange: "debuglab", symbol: "LAB")
        replaceSubscriptions(owner: owner, with: [scratch])
        replaceSubscriptions(owner: owner, with: [scratch2])
        replaceSubscriptions(owner: owner, with: [scratch, scratch2])
        replaceSubscriptions(owner: owner, with: [])
    }

    /// Replays a deterministic 1,000-ticker burst through the decode path to
    /// exercise coalescing and the metrics pipeline. Requires a connection.
    func debugReplayFixtureBurst() {
        guard connection != nil else { return }
        let gen = generation
        for index in 0..<1000 {
            let message = """
            {"type":"ticker","exchange":"debuglab","symbol":"LAB","data":{"price":\(100 + index % 50),"timestamp":\(1_700_000_000_000 + index)}}
            """
            handleText(message, generation: gen)
        }
    }
}
#endif

extension Duration {
    var asSeconds: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}

/// os.Logger categories for the realtime pipeline. Values logged are states,
/// generations, and counters — never payloads, tokens, or user identifiers.
enum RealtimeLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.cryptory.app"

    static let connection = Logger(subsystem: subsystem, category: "realtime.connection")
    static let subscription = Logger(subsystem: subsystem, category: "realtime.subscription")
    static let message = Logger(subsystem: subsystem, category: "realtime.message")
    static let heartbeat = Logger(subsystem: subsystem, category: "realtime.heartbeat")
    static let performance = Logger(subsystem: subsystem, category: "realtime.performance")
}
