import Foundation

/// Connection state owned exclusively by `MarketStreamEngine`.
enum MarketStreamConnectionState: Equatable, Sendable {
    /// No connection and none desired (no subscriptions, or manual disconnect).
    case idle
    /// A transport connection for `generation` is being established.
    case connecting(generation: UInt64)
    /// The transport for `generation` is open.
    case connected(generation: UInt64)
    /// The last connection failed; a reconnect is scheduled.
    case waitingToReconnect(generation: UInt64, attempt: Int, reason: String)
    /// The app is in the background; the socket is closed but subscriptions
    /// are retained for foreground restoration.
    case suspended

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    /// Mapping to the legacy `PublicWebSocketConnectionState` consumed by
    /// `CryptoViewModel` through the compatibility adapter.
    var legacyState: PublicWebSocketConnectionState {
        switch self {
        case .idle, .suspended:
            return .disconnected
        case .connecting:
            return .connecting
        case .connected:
            return .connected
        case .waitingToReconnect(_, _, let reason):
            return .failed(reason)
        }
    }
}

/// Why the engine last entered the reconnect path. Reasons are short static
/// descriptions — never raw payloads or URLs with credentials.
enum MarketStreamDisconnectReason: Equatable, Sendable {
    case transportError(String)
    case connectionClosed(code: Int?)
    case heartbeatTimeout
    case manual
    case background
    case idle

    var description: String {
        switch self {
        case .transportError(let message):
            return message
        case .connectionClosed(let code):
            return "connection closed (code: \(code.map(String.init) ?? "none"))"
        case .heartbeatTimeout:
            return "heartbeat timeout"
        case .manual:
            return "manual disconnect"
        case .background:
            return "app backgrounded"
        case .idle:
            return "no active subscriptions"
        }
    }
}
