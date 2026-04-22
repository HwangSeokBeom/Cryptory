import Foundation

enum AppLogCategory: String {
    case lifecycle = "LIFECYCLE"
    case route = "ROUTE"
    case auth = "AUTH"
    case network = "NETWORK"
    case websocket = "WEBSOCKET"
}

enum AppLogger {
    nonisolated(unsafe) private static let counterLock = NSLock()
    nonisolated(unsafe) private static var instanceCounters: [String: Int] = [:]

    nonisolated static func debug(_ category: AppLogCategory, _ message: String) {
        #if DEBUG
        print("[\(category.rawValue)] \(message)")
        #endif
    }

    nonisolated static func nextInstanceID(scope: String) -> Int {
        counterLock.lock()
        defer { counterLock.unlock() }

        let nextValue = (instanceCounters[scope] ?? 0) + 1
        instanceCounters[scope] = nextValue
        return nextValue
    }

    static func masked(_ value: String?) -> String {
        guard let value, !value.isEmpty else {
            return "<empty>"
        }

        if value.count <= 6 {
            return String(repeating: "*", count: value.count)
        }

        let prefix = value.prefix(3)
        let suffix = value.suffix(2)
        return "\(prefix)\(String(repeating: "*", count: max(value.count - 5, 0)))\(suffix)"
    }

    static func sanitizedMetadata(_ metadata: [String: String]) -> String {
        let sanitizedPairs = metadata.map { key, value in
            let normalizedKey = key.lowercased()
            if normalizedKey.contains("secret") || normalizedKey.contains("token") || normalizedKey.contains("access") || normalizedKey.contains("key") {
                return "\(key)=\(masked(value))"
            }
            return "\(key)=\(value)"
        }

        return sanitizedPairs.sorted().joined(separator: ", ")
    }
}

enum MarketPerformanceMetric: String {
    case exchangeSwitchElapsed = "exchange_switch_elapsed"
    case initialVisibleFirstPaintElapsed = "initial_visible_first_paint_elapsed"
    case skeletonShown = "skeleton_shown"
    case skeletonHidden = "skeleton_hidden"
    case marketRowsApply = "market_rows_apply"
    case visibleRowReconfigure = "visible_row_reconfigure"
    case offscreenBatch = "offscreen_batch"
    case graphOnlyPatch = "graph_only_patch"
    case imageOnlyPatch = "image_only_patch"
    case flashOnlyPatch = "flash_only_patch"
    case baseTickerRefresh = "base_ticker_refresh"
    case coalescedPatch = "coalesced_patch"
    case placeholderFinal = "placeholder_final"
    case noImageURL = "no_image_url"
    case graphLayoutZero = "graph_layout_zero"
}

final class MarketPerformanceDebugClient: @unchecked Sendable {
    static let shared = MarketPerformanceDebugClient()

    private let lock = NSLock()
    private var counters: [MarketPerformanceMetric: Int] = [:]

    func increment(_ metric: MarketPerformanceMetric, by amount: Int = 1) {
        #if DEBUG
        lock.lock()
        counters[metric, default: 0] += amount
        lock.unlock()
        #endif
    }

    func log(
        _ metric: MarketPerformanceMetric,
        exchange: Exchange?,
        details: [String: String] = [:]
    ) {
        #if DEBUG
        increment(metric)
        var mergedDetails = details
        mergedDetails["metric"] = metric.rawValue
        if let exchange {
            mergedDetails["exchange"] = exchange.rawValue
        }
        AppLogger.debug(
            .lifecycle,
            "[MarketPerformance] \(AppLogger.sanitizedMetadata(mergedDetails))"
        )
        #endif
    }

    func snapshotCounters() -> [String: Int] {
        #if DEBUG
        lock.lock()
        defer { lock.unlock() }
        return Dictionary(uniqueKeysWithValues: counters.map { ($0.key.rawValue, $0.value) })
        #else
        return [:]
        #endif
    }
}
