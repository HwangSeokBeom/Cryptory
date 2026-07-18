import Foundation

/// A single event delivered by a live WebSocket connection.
enum WebSocketTransportEvent: Sendable {
    case opened
    case text(String)
    case closed(code: Int?, reason: String?)
}

/// One live socket connection. Created by a `WebSocketTransport`, owned by the
/// `MarketStreamEngine` for exactly one connection generation, then discarded.
///
/// A connection never mutates engine or UI state; it only yields events and
/// accepts sends. `events` finishes when the connection ends (throwing on
/// transport failure).
protocol WebSocketTransportConnection: Sendable {
    var events: AsyncThrowingStream<WebSocketTransportEvent, Error> { get }

    func send(text: String) async throws

    /// Sends a protocol-level ping and suspends until the matching pong
    /// arrives, throwing on failure. The caller enforces its own timeout.
    func sendPing() async throws

    /// Closes the connection. Idempotent; `events` finishes afterwards.
    func close()
}

/// Factory for socket connections. The production implementation wraps
/// `URLSessionWebSocketTask`; tests use a scripted implementation.
protocol WebSocketTransport: Sendable {
    func open(url: URL) -> any WebSocketTransportConnection
}
