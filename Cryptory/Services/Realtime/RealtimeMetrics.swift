import Foundation

/// Mutable metrics collector owned by `MarketStreamEngine`.
///
/// Counters are grouped by pipeline stage so global and per-consumer
/// quantities are never mixed:
///
/// **Ingress (global):** one count per raw frame handed over by the
/// transport, split into decoded market events, control messages, and
/// decode failures. Valid conservation:
/// `transportFramesReceived == messagesDecoded + controlMessages + decodeFailures`.
///
/// **Engine emission (global):** `logicalEventsEmitted` counts every logical
/// `MarketStreamEvent` the engine dispatches (market events and
/// connection-state events), independent of how many consumers exist.
///
/// **Delivery (aggregated across consumers):** each dispatched event is
/// enqueued once per registered consumer (`consumerEnqueues`), after which it
/// is either delivered (`consumerDeliveries`), coalesced/replaced/merged by
/// the per-kind buffer policy, dropped by an explicit bound, or discarded
/// (counted) when its consumer unregisters. Valid conservation at any
/// quiescent point:
/// `consumerEnqueues == consumerDeliveries + tickerEventsCoalesced
///  + orderbookSnapshotsReplaced + candleUpdatesMergedOrReplaced
///  + tradeEventsDropped + bufferEventsDropped + (events still pending in
///  live consumer buffers)`.
///
/// Global decoded counts must never be compared against per-consumer
/// delivery counts — with N consumers one decoded event fans out N times.
///
/// Memory is bounded by construction: all fields are scalars except the
/// latency samples, which live in a fixed-size ring buffer.
struct RealtimeMetrics {
    // Ingress (global)
    private(set) var transportFramesReceived = 0
    private(set) var messagesDecoded = 0
    private(set) var controlMessages = 0
    private(set) var decodeFailures = 0

    // Engine emission (global)
    private(set) var logicalEventsEmitted = 0

    // Delivery (aggregated across consumer buffers)
    private(set) var consumerEnqueues = 0
    private(set) var consumerDeliveries = 0
    private(set) var tickerEventsCoalesced = 0
    private(set) var orderbookSnapshotsReplaced = 0
    private(set) var candleUpdatesMergedOrReplaced = 0
    /// Oldest trade batch dropped by the per-market trade bound.
    private(set) var tradeEventsDropped = 0
    /// Events dropped by the total-capacity backstop or discarded (counted)
    /// when their consumer unregistered or was cancelled.
    private(set) var bufferEventsDropped = 0

    private(set) var staleEventsIgnored = 0

    private(set) var reconnectCount = 0
    private(set) var consecutiveReconnectFailures = 0
    private(set) var lastDisconnectReason: String?

    private(set) var heartbeatSuccessCount = 0
    private(set) var heartbeatFailureCount = 0

    private(set) var latestEventLatency: Double?
    private(set) var maxBufferUsage = 0

    private var latencyRing: [Double]
    private var latencyRingIndex = 0
    private var latencyRingCount = 0

    init(latencySampleCapacity: Int = 256) {
        latencyRing = Array(repeating: 0, count: max(latencySampleCapacity, 1))
    }

    mutating func recordTransportFrameReceived() { transportFramesReceived += 1 }
    mutating func recordMessageDecoded() { messagesDecoded += 1 }
    mutating func recordControlMessage() { controlMessages += 1 }
    mutating func recordDecodeFailure() { decodeFailures += 1 }

    mutating func recordLogicalEventEmitted() { logicalEventsEmitted += 1 }

    mutating func recordConsumerEnqueue() { consumerEnqueues += 1 }
    mutating func recordTickerCoalesced() { tickerEventsCoalesced += 1 }
    mutating func recordOrderbookSnapshotReplaced() { orderbookSnapshotsReplaced += 1 }
    mutating func recordCandleUpdateMerged() { candleUpdatesMergedOrReplaced += 1 }
    mutating func recordTradeEventsDropped(_ count: Int) { tradeEventsDropped += count }
    mutating func recordBufferEventsDropped(_ count: Int) { bufferEventsDropped += count }
    mutating func recordStaleEventIgnored() { staleEventsIgnored += 1 }
    mutating func recordHeartbeatSuccess() { heartbeatSuccessCount += 1 }
    mutating func recordHeartbeatFailure() { heartbeatFailureCount += 1 }

    mutating func recordReconnectScheduled(reason: String) {
        reconnectCount += 1
        consecutiveReconnectFailures += 1
        lastDisconnectReason = reason
    }

    mutating func recordConnectionStable() {
        consecutiveReconnectFailures = 0
    }

    mutating func recordDisconnect(reason: String) {
        lastDisconnectReason = reason
    }

    mutating func recordConsumerDelivery(latency: Double) {
        consumerDeliveries += 1
        latestEventLatency = latency
        latencyRing[latencyRingIndex] = latency
        latencyRingIndex = (latencyRingIndex + 1) % latencyRing.count
        latencyRingCount = min(latencyRingCount + 1, latencyRing.count)
    }

    mutating func recordBufferUsage(_ usage: Int) {
        maxBufferUsage = max(maxBufferUsage, usage)
    }

    func latencyPercentiles() -> (p50: Double?, p95: Double?) {
        guard latencyRingCount > 0 else { return (nil, nil) }
        let samples = Array(latencyRing.prefix(latencyRingCount)).sorted()
        func percentile(_ fraction: Double) -> Double {
            let position = fraction * Double(samples.count - 1)
            let lower = Int(position)
            let upper = min(lower + 1, samples.count - 1)
            let weight = position - Double(lower)
            return samples[lower] * (1 - weight) + samples[upper] * weight
        }
        return (percentile(0.5), percentile(0.95))
    }
}
