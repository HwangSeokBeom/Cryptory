import Foundation

/// Exponential backoff with bounded jitter for reconnect scheduling.
///
/// Retries continue indefinitely while at least one subscription is active;
/// the engine stops retrying on manual disconnect, background suspension, or
/// when the subscription registry becomes empty (documented in
/// Docs/REALTIME_PIPELINE.md).
///
/// Backoff does not reset when a socket merely opens; the engine resets it
/// only when the connection proves useful (first decoded market event or
/// first successful heartbeat pong on the current generation).
struct ReconnectPolicy: Sendable {
    var initialDelay: Duration = .seconds(1)
    var multiplier: Double = 2.0
    var maxDelay: Duration = .seconds(30)
    /// Fraction of the computed delay used as the jitter band (0.2 = ±20 %).
    var jitterRatio: Double = 0.2

    /// Delay before reconnect attempt `attempt` (1-based).
    ///
    /// - Parameter jitterUnit: a uniform random sample in `[0, 1)`, injected
    ///   so tests can pin jitter deterministically.
    func delay(forAttempt attempt: Int, jitterUnit: Double) -> Duration {
        precondition(attempt >= 1, "reconnect attempts are 1-based")
        let base = Self.seconds(initialDelay) * pow(multiplier, Double(attempt - 1))
        let capped = min(base, Self.seconds(maxDelay))
        let clampedUnit = min(max(jitterUnit, 0), 1)
        let jitterFactor = 1.0 + jitterRatio * (2.0 * clampedUnit - 1.0)
        return .seconds(max(capped * jitterFactor, 0))
    }

    private static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }
}

/// Heartbeat cadence. The backend protocol has no documented application-level
/// ping, so the engine uses transport-level (`URLSessionWebSocketTask`) pings.
struct HeartbeatPolicy: Sendable {
    /// Interval between pings while connected.
    var pingInterval: Duration = .seconds(20)
    /// Time allowed for the pong before the connection is treated as half-open.
    var pongTimeout: Duration = .seconds(10)
}
