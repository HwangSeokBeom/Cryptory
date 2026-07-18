import Foundation

/// Immutable, `Sendable` view of the engine's in-memory metrics.
///
/// Contains no payloads, tokens, or user identifiers — only counters, states,
/// and latency aggregates. Safe to display in the DEBUG Pipeline Lab.
struct RealtimeMetricsSnapshot: Equatable, Sendable {
    var connectionState: MarketStreamConnectionState = .idle
    var generation: UInt64 = 0
    /// Engine-clock timestamp (elapsed duration) when the current connection
    /// opened; nil when not connected.
    var connectedAt: Duration?
    var uptime: Duration = .zero

    var activeSubscriptionCount = 0
    var upstreamSubscriptionCount = 0

    var messagesReceived = 0
    var messagesDecoded = 0
    var decodeFailures = 0
    var messagesEmitted = 0
    var tickersCoalesced = 0
    var eventsDropped = 0
    var staleEventsIgnored = 0

    var reconnectCount = 0
    var consecutiveReconnectFailures = 0
    var lastDisconnectReason: String?

    var heartbeatSuccessCount = 0
    var heartbeatFailureCount = 0

    /// Seconds between enqueue into the consumer buffer and consumer dequeue
    /// for the most recent emitted event.
    var latestEventLatency: Double?
    var latencyP50: Double?
    var latencyP95: Double?

    var maxBufferUsage = 0
}
