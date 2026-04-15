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
}
