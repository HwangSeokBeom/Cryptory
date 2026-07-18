import Foundation

/// Mutable metrics collector owned by `MarketStreamEngine`.
///
/// Memory is bounded by construction: all fields are scalars except the
/// latency samples, which live in a fixed-size ring buffer.
struct RealtimeMetrics {
    private(set) var messagesReceived = 0
    private(set) var messagesDecoded = 0
    private(set) var decodeFailures = 0
    private(set) var messagesEmitted = 0
    private(set) var tickersCoalesced = 0
    private(set) var eventsDropped = 0
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

    mutating func recordMessageReceived() { messagesReceived += 1 }
    mutating func recordMessageDecoded() { messagesDecoded += 1 }
    mutating func recordDecodeFailure() { decodeFailures += 1 }
    mutating func recordTickerCoalesced() { tickersCoalesced += 1 }
    mutating func recordEventsDropped(_ count: Int) { eventsDropped += count }
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

    mutating func recordEmission(latency: Double) {
        messagesEmitted += 1
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
