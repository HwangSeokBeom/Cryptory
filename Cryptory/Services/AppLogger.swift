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
