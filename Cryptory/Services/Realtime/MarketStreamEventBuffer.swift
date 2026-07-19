import Foundation

/// Bounded pending-event buffer for one engine consumer.
///
/// Implements the per-kind policies documented in Docs/REALTIME_PIPELINE.md:
/// - connection-state events: never coalesced, dropped only as a last resort;
/// - tickers: latest value per market replaces the pending one;
/// - orderbook snapshots: latest replaces the pending one per market;
/// - candles: latest update per (market, interval) replaces the pending one,
///   merging candle arrays by candle timestamp;
/// - trades: appended, bounded per market (oldest batch dropped, counted);
/// - total capacity bounded (oldest non-state event dropped, counted).
///
/// Owned and mutated only by `MarketStreamEngine`.
struct MarketStreamEventBuffer {
    struct Queued {
        var event: MarketStreamEvent
        var enqueuedAt: Duration
    }

    struct EnqueueResult {
        var coalescedTicker = false
        var replacedOrderbook = false
        var mergedCandle = false
        /// Oldest batch dropped by the per-market trade bound.
        var droppedTradeBatches = 0
        /// Events dropped by the total-capacity backstop.
        var droppedByCapacity = 0

        var totalDropped: Int { droppedTradeBatches + droppedByCapacity }
    }

    /// `nil` entries are tombstones left by mid-queue drops.
    private var storage: [Queued?] = []
    private var head = 0
    private var liveCount = 0
    /// Absolute storage index of the pending event per coalescing key.
    private var pendingKeyIndex: [String: Int] = [:]
    /// Absolute storage indices of pending trade batches per market, oldest first.
    private var tradeIndices: [String: [Int]] = [:]

    var count: Int { liveCount }
    var isEmpty: Bool { liveCount == 0 }

    mutating func enqueue(
        _ event: MarketStreamEvent,
        at now: Duration,
        capacity: Int,
        maxTradeBatchesPerMarket: Int
    ) -> EnqueueResult {
        var result = EnqueueResult()

        if let key = event.coalescingKey, let index = pendingKeyIndex[key] {
            let previous = storage[index]?.event
            let merged = Self.merge(pending: previous, incoming: event)
            storage[index] = Queued(event: merged, enqueuedAt: now)
            switch event {
            case .ticker:
                result.coalescedTicker = true
            case .orderbook:
                result.replacedOrderbook = true
            case .candles:
                result.mergedCandle = true
            case .trades, .connectionState:
                break
            }
            return result
        }

        if let tradeKey = event.tradeBufferKey {
            var indices = tradeIndices[tradeKey, default: []]
            if indices.count >= maxTradeBatchesPerMarket, let oldest = indices.first {
                storage[oldest] = nil
                indices.removeFirst()
                liveCount -= 1
                result.droppedTradeBatches += 1
            }
            indices.append(storage.count)
            tradeIndices[tradeKey] = indices
        }

        if let key = event.coalescingKey {
            pendingKeyIndex[key] = storage.count
        }
        storage.append(Queued(event: event, enqueuedAt: now))
        liveCount += 1

        if liveCount > capacity {
            result.droppedByCapacity += dropOldestDroppable()
        }

        compactIfNeeded()
        return result
    }

    mutating func dequeue() -> Queued? {
        while head < storage.count {
            let index = head
            head += 1
            guard let queued = storage[index] else { continue }
            storage[index] = nil
            liveCount -= 1
            forgetIndex(index, event: queued.event)
            compactIfNeeded()
            return queued
        }
        return nil
    }

    mutating func removeAll() {
        storage = []
        head = 0
        liveCount = 0
        pendingKeyIndex = [:]
        tradeIndices = [:]
    }

    /// Drops the oldest event that is not a connection-state event; if only
    /// state events remain, drops the oldest of those. Returns dropped count.
    private mutating func dropOldestDroppable() -> Int {
        var stateIndex: Int?
        for index in head..<storage.count {
            guard let queued = storage[index] else { continue }
            if case .connectionState = queued.event {
                if stateIndex == nil { stateIndex = index }
                continue
            }
            remove(at: index, event: queued.event)
            return 1
        }
        if let index = stateIndex, let queued = storage[index] {
            remove(at: index, event: queued.event)
            return 1
        }
        return 0
    }

    private mutating func remove(at index: Int, event: MarketStreamEvent) {
        storage[index] = nil
        liveCount -= 1
        forgetIndex(index, event: event)
    }

    private mutating func forgetIndex(_ index: Int, event: MarketStreamEvent) {
        if let key = event.coalescingKey, pendingKeyIndex[key] == index {
            pendingKeyIndex.removeValue(forKey: key)
        }
        if let tradeKey = event.tradeBufferKey, var indices = tradeIndices[tradeKey] {
            if let position = indices.firstIndex(of: index) {
                indices.remove(at: position)
            }
            if indices.isEmpty {
                tradeIndices.removeValue(forKey: tradeKey)
            } else {
                tradeIndices[tradeKey] = indices
            }
        }
    }

    /// Rebuilds storage once the tombstone/consumed prefix grows large so the
    /// arrays and index maps stay small regardless of throughput.
    private mutating func compactIfNeeded() {
        guard head > 512 || storage.count - liveCount > 1024 else { return }
        var newStorage: [Queued?] = []
        newStorage.reserveCapacity(liveCount)
        var remap: [Int: Int] = [:]
        for index in head..<storage.count {
            if let queued = storage[index] {
                remap[index] = newStorage.count
                newStorage.append(queued)
            }
        }
        storage = newStorage
        head = 0
        pendingKeyIndex = pendingKeyIndex.compactMapValues { remap[$0] }
        tradeIndices = tradeIndices.compactMapValues { indices in
            let mapped = indices.compactMap { remap[$0] }
            return mapped.isEmpty ? nil : mapped
        }
    }

    /// Merge policy for coalescable events. Tickers and orderbooks keep the
    /// newest payload wholesale; candle updates for the same (market,
    /// interval) merge by candle timestamp with the newest data winning.
    private static func merge(pending: MarketStreamEvent?, incoming: MarketStreamEvent) -> MarketStreamEvent {
        guard
            case .candles(let newPayload) = incoming,
            case .candles(let oldPayload)? = pending,
            oldPayload.interval == newPayload.interval
        else {
            return incoming
        }
        var byTime: [Int: CandleData] = [:]
        for candle in oldPayload.candles {
            byTime[candle.time] = candle
        }
        for candle in newPayload.candles {
            byTime[candle.time] = candle
        }
        let mergedCandles = byTime.values.sorted { $0.time < $1.time }
        return .candles(
            CandleStreamPayload(
                symbol: newPayload.symbol,
                exchange: newPayload.exchange,
                interval: newPayload.interval,
                candles: mergedCandles
            )
        )
    }
}
