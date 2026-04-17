import Foundation

enum AppLogCategory: String {
    case route = "ROUTE"
    case auth = "AUTH"
    case network = "NETWORK"
    case websocket = "WEBSOCKET"
}

enum AppLogger {
    static func debug(_ category: AppLogCategory, _ message: String) {
        #if DEBUG
        print("[\(category.rawValue)] \(message)")
        #endif
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
