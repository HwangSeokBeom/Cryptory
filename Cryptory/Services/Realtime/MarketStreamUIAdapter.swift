import Foundation
import UIKit

/// Compatibility adapter: exposes the actor-isolated `MarketStreamEngine`
/// through the legacy `PublicWebSocketServicing` closure protocol so
/// `CryptoViewModel` and every existing screen keep working unchanged.
///
/// - Consumes the engine's `AsyncStream` and delivers every callback on
///   `MainActor`.
/// - Serializes `connect` / `disconnect` / `updateSubscriptions` through a
///   command stream so rapid calls apply to the engine in call order.
/// - Observes app lifecycle notifications and forwards the documented
///   suspend/resume policy (close socket in background, restore
///   subscriptions in foreground) — see Docs/REALTIME_PIPELINE.md.
///
/// Lifecycle: neither internal task retains `self` across suspensions (the
/// consume loop reacquires a weak reference per event only), so dropping the
/// last strong reference deallocates the adapter and `deinit` runs its
/// safety cleanup. `shutdown()` is the explicit, idempotent teardown —
/// correctness does not depend on `deinit` alone. Cancelling the consume
/// task releases engine-side ownership (consumer, buffer, subscriptions;
/// the engine closes the socket when the final owner leaves).
///
/// Migration path: once `CryptoViewModel` consumes `MarketStreamEvent`
/// directly, this adapter and the legacy protocol can be deleted.
@MainActor
final class MarketStreamUIAdapter: @MainActor PublicWebSocketServicing {
    var onConnectionStateChange: ((PublicWebSocketConnectionState) -> Void)?
    var onTickerReceived: ((TickerStreamPayload) -> Void)?
    var onOrderbookReceived: ((OrderbookStreamPayload) -> Void)?
    var onTradesReceived: ((TradesStreamPayload) -> Void)?
    var onCandlesReceived: ((CandleStreamPayload) -> Void)?

    /// Exposed for the DEBUG Realtime Pipeline Lab.
    let engine: MarketStreamEngine

    private enum Command {
        case connect
        case disconnect
        case replaceSubscriptions(Set<PublicMarketSubscription>)
        case suspend
        case resume
    }

    private let commands: AsyncStream<Command>.Continuation
    private var pumpTask: Task<Void, Never>?
    private var consumeTask: Task<Void, Never>?
    private var lastLegacyState: PublicWebSocketConnectionState?
    private var lifecycleObservers: [NSObjectProtocol] = []
    private var isShutdown = false

    init(engine: MarketStreamEngine, observesAppLifecycle: Bool = true) {
        self.engine = engine

        let (stream, continuation) = AsyncStream<Command>.makeStream()
        self.commands = continuation

        // The pump owns the engine consumer registration. It captures the
        // engine and the command stream, never `self` (a weak reference is
        // used once to hand the event stream to the consume loop), so it
        // cannot keep the adapter alive.
        pumpTask = Task { [engine, weak self] in
            let (ownerID, events) = await engine.register()
            self?.startConsuming(events)
            for await command in stream {
                switch command {
                case .connect:
                    await engine.connect()
                case .disconnect:
                    await engine.disconnect()
                case .replaceSubscriptions(let subscriptions):
                    await engine.replaceSubscriptions(owner: ownerID, with: subscriptions)
                case .suspend:
                    await engine.suspend()
                case .resume:
                    await engine.resume()
                }
            }
            // Idempotent with the engine-side release performed when the
            // consume task is cancelled.
            await engine.unregister(ownerID)
        }

        if observesAppLifecycle {
            observeAppLifecycle(continuation: continuation)
        }
    }

    convenience init(runtimeConfiguration: AppRuntimeConfiguration = .live) {
        self.init(
            engine: MarketStreamEngine(
                url: runtimeConfiguration.publicMarketWebSocketURL,
                transport: URLSessionWebSocketTransport()
            )
        )
    }

    isolated deinit {
        // Nonblocking safety net only — explicit shutdown() is the contract.
        shutdown()
    }

    /// Explicit, idempotent teardown: stops accepting commands, cancels the
    /// command and consumer tasks (cancellation releases the engine-side
    /// consumer, its buffer, and its subscriptions; the engine disconnects
    /// when no other owner remains), removes lifecycle observers, and stops
    /// callback delivery. Safe to call repeatedly.
    func shutdown() {
        guard !isShutdown else { return }
        isShutdown = true
        onConnectionStateChange = nil
        onTickerReceived = nil
        onOrderbookReceived = nil
        onTradesReceived = nil
        onCandlesReceived = nil
        commands.finish()
        pumpTask?.cancel()
        pumpTask = nil
        consumeTask?.cancel()
        consumeTask = nil
        for observer in lifecycleObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        lifecycleObservers = []
    }

    // MARK: - PublicWebSocketServicing

    func connect() {
        guard !isShutdown else { return }
        commands.yield(.connect)
    }

    func disconnect() {
        guard !isShutdown else { return }
        commands.yield(.disconnect)
    }

    func updateSubscriptions(_ subscriptions: Set<PublicMarketSubscription>) {
        guard !isShutdown else { return }
        commands.yield(.replaceSubscriptions(subscriptions))
    }

    // MARK: - Event delivery (MainActor)

    private func startConsuming(_ events: AsyncStream<MarketStreamEvent>) {
        guard consumeTask == nil, !isShutdown else { return }
        // The loop must not retain `self` while suspended waiting for the
        // next event: it reacquires a weak reference per delivered event and
        // releases it before suspending again, so the adapter can deallocate
        // while the stream is idle.
        consumeTask = Task { [weak self] in
            for await event in events {
                guard let self, !self.isShutdown else { return }
                self.deliver(event)
            }
        }
    }

    private func deliver(_ event: MarketStreamEvent) {
        switch event {
        case .connectionState(let state):
            let legacy = state.legacyState
            // The legacy service only notified on changes; several engine
            // states map to the same legacy value, so de-duplicate here.
            guard legacy != lastLegacyState else { return }
            lastLegacyState = legacy
            onConnectionStateChange?(legacy)
        case .ticker(let payload):
            onTickerReceived?(payload)
        case .orderbook(let payload):
            onOrderbookReceived?(payload)
        case .trades(let payload):
            onTradesReceived?(payload)
        case .candles(let payload):
            onCandlesReceived?(payload)
        }
    }

#if DEBUG
    // Test introspection only.
    var debugLifecycleObserverCount: Int { lifecycleObservers.count }
    var debugIsShutdown: Bool { isShutdown }
#endif

    // MARK: - App lifecycle

    private func observeAppLifecycle(continuation: AsyncStream<Command>.Continuation) {
        let center = NotificationCenter.default
        lifecycleObservers.append(
            center.addObserver(
                forName: UIApplication.didEnterBackgroundNotification,
                object: nil,
                queue: .main
            ) { _ in
                continuation.yield(.suspend)
            }
        )
        lifecycleObservers.append(
            center.addObserver(
                forName: UIApplication.willEnterForegroundNotification,
                object: nil,
                queue: .main
            ) { _ in
                continuation.yield(.resume)
            }
        )
    }
}
