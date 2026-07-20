import Foundation

/// A single event delivered by a live WebSocket connection.
enum WebSocketTransportEvent: Sendable {
    case opened
    case text(String)
    case closed(code: Int?, reason: String?)
}

/// Transport-level terminal conditions surfaced by `receive()`.
enum WebSocketTransportError: Error, Sendable {
    /// The connection has ended (closed locally or remotely); no further
    /// events will be delivered.
    case ended
}

/// One live socket connection. Created by a `WebSocketTransport`, owned by the
/// `MarketStreamEngine` for exactly one connection generation, then discarded.
///
/// A connection never mutates engine or UI state; it only answers `receive()`
/// calls and accepts sends.
///
/// **Pull-based ingress contract (bounded by construction):** the engine is
/// the only caller of `receive()` and never has more than one call
/// outstanding — the next frame is not requested until the engine has
/// accepted the current one. The transport therefore holds at most one
/// undelivered frame at a time; there is no transport-side queue in which
/// raw (undecoded) orderbook/trade/candle frames can accumulate, and no raw
/// frame is ever silently dropped. Any producer-side backlog stays outside
/// the process (network/kernel buffers), where TCP flow control applies.
protocol WebSocketTransportConnection: Sendable {
    /// Suspends until the next transport event and returns it.
    ///
    /// - Throws: the underlying transport error on failure,
    ///   `WebSocketTransportError.ended` once the connection has terminated,
    ///   and `CancellationError` when the awaiting task is cancelled or the
    ///   connection is closed while a receive is pending.
    /// - After `.closed` has been returned (or any error thrown), subsequent
    ///   calls throw.
    func receive() async throws -> WebSocketTransportEvent

    func send(text: String) async throws

    /// Sends a protocol-level ping and suspends until the matching pong
    /// arrives, throwing on failure. The caller enforces its own timeout.
    func sendPing() async throws

    /// Closes the connection. Idempotent; a pending `receive()` resumes by
    /// throwing, and later calls throw `WebSocketTransportError.ended`.
    func close()
}

/// Factory for socket connections. The production implementation wraps
/// `URLSessionWebSocketTask`; tests use a scripted implementation.
protocol WebSocketTransport: Sendable {
    func open(url: URL) -> any WebSocketTransportConnection
}
