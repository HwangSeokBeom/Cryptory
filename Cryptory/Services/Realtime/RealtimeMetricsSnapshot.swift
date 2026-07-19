import Foundation

/// Immutable, `Sendable` view of the engine's in-memory metrics.
///
/// Contains no payloads, tokens, or user identifiers — only counters, states,
/// and latency aggregates. Safe to display in the DEBUG Pipeline Lab.
///
/// Counter groups and their valid conservation equations are documented on
/// `RealtimeMetrics`; in particular, global decoded counts (`messagesDecoded`)
/// must never be compared against per-consumer delivery counts
/// (`consumerDeliveries`) — one decoded event fans out once per consumer.
struct RealtimeMetricsSnapshot: Equatable, Sendable {
    var connectionState: MarketStreamConnectionState = .idle
    var generation: UInt64 = 0
    /// Engine-clock timestamp (elapsed duration) when the current connection
    /// opened; nil when not connected.
    var connectedAt: Duration?
    var uptime: Duration = .zero

    var activeSubscriptionCount = 0
    var upstreamSubscriptionCount = 0
    var registeredConsumerCount = 0

    // Ingress (global)
    var transportFramesReceived = 0
    var messagesDecoded = 0
    var controlMessages = 0
    var decodeFailures = 0

    // Engine emission (global)
    var logicalEventsEmitted = 0

    // Delivery (aggregated across consumers)
    var consumerEnqueues = 0
    var consumerDeliveries = 0
    var tickerEventsCoalesced = 0
    var orderbookSnapshotsReplaced = 0
    var candleUpdatesMergedOrReplaced = 0
    var tradeEventsDropped = 0
    var bufferEventsDropped = 0

    var staleEventsIgnored = 0

    var reconnectCount = 0
    var consecutiveReconnectFailures = 0
    var lastDisconnectReason: String?

    var heartbeatSuccessCount = 0
    var heartbeatFailureCount = 0

    /// Seconds between enqueue into the consumer buffer and consumer dequeue
    /// for the most recent delivered event.
    var latestEventLatency: Double?
    var latencyP50: Double?
    var latencyP95: Double?

    var maxBufferUsage = 0
}
