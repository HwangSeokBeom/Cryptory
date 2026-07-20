#if DEBUG
import Combine
import Foundation

/// View model for the DEBUG-only Realtime Pipeline Lab: polls the engine's
/// bounded metrics snapshot and forwards simulation actions.
///
/// Compiled out of Release builds entirely.
@MainActor
final class RealtimePipelineLabViewModel: ObservableObject {
    @Published private(set) var snapshot = RealtimeMetricsSnapshot()
    @Published private(set) var lastActionDescription: String?

    private let engine: MarketStreamEngine
    private var pollTask: Task<Void, Never>?

    init(engine: MarketStreamEngine) {
        self.engine = engine
    }

    func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self, engine] in
            while !Task.isCancelled {
                let snapshot = await engine.metricsSnapshot()
                guard let self else { return }
                self.snapshot = snapshot
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: - Simulations (local engine only; cannot touch production users)

    func simulateConnectionFailure() {
        lastActionDescription = "Simulated connection failure"
        Task { await engine.debugSimulateConnectionFailure() }
    }

    func simulateHeartbeatTimeout() {
        lastActionDescription = "Simulated heartbeat timeout"
        Task { await engine.debugSimulateHeartbeatTimeout() }
    }

    func simulateRapidSubscriptionReplacement() {
        lastActionDescription = "Simulated rapid subscription replacement"
        Task { await engine.debugSimulateRapidSubscriptionReplacement() }
    }

    func replayFixtureBurst() {
        lastActionDescription = "Replayed 1k-ticker fixture burst"
        Task { await engine.debugReplayFixtureBurst() }
    }

    // MARK: - Formatting

    var stateDescription: String {
        switch snapshot.connectionState {
        case .idle: return "Idle"
        case .connecting(let generation): return "Connecting (gen \(generation))"
        case .connected(let generation): return "Connected (gen \(generation))"
        case .waitingToReconnect(_, let attempt, let reason):
            return "Reconnecting (attempt \(attempt)) — \(reason)"
        case .suspended: return "Suspended (background)"
        }
    }

    var uptimeDescription: String {
        let seconds = Int(snapshot.uptime.asSeconds)
        guard seconds > 0 else { return "—" }
        return "\(seconds / 60)m \(seconds % 60)s"
    }

    func latencyDescription(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f ms", value * 1000)
    }
}
#endif
