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

    init(engine: MarketStreamEngine, observesAppLifecycle: Bool = true) {
        self.engine = engine

        let (stream, continuation) = AsyncStream<Command>.makeStream()
        self.commands = continuation

        pumpTask = Task { [engine] in
            let (ownerID, events) = await engine.register()
            self.startConsuming(events)
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
        commands.finish()
        pumpTask?.cancel()
        consumeTask?.cancel()
        for observer in lifecycleObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - PublicWebSocketServicing

    func connect() {
        commands.yield(.connect)
    }

    func disconnect() {
        commands.yield(.disconnect)
    }

    func updateSubscriptions(_ subscriptions: Set<PublicMarketSubscription>) {
        commands.yield(.replaceSubscriptions(subscriptions))
    }

    // MARK: - Event delivery (MainActor)

    private func startConsuming(_ events: AsyncStream<MarketStreamEvent>) {
        guard consumeTask == nil else { return }
        consumeTask = Task {
            for await event in events {
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
