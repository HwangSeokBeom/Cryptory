import Foundation
import Synchronization
@testable import Cryptory

enum ScriptedTransportError: Error {
    case scriptedFailure(String)
    case pingFailed
}

/// Test transport: records every opened connection and lets the test script
/// transport events (open, text, close, failure) deterministically.
final class ScriptedWebSocketTransport: WebSocketTransport {
    private struct State {
        var connections: [ScriptedWebSocketConnection] = []
    }

    private let state = Mutex(State())

    var openCount: Int {
        state.withLock { $0.connections.count }
    }

    var connections: [ScriptedWebSocketConnection] {
        state.withLock { $0.connections }
    }

    var lastConnection: ScriptedWebSocketConnection? {
        state.withLock { $0.connections.last }
    }

    func open(url: URL) -> any WebSocketTransportConnection {
        let connection = ScriptedWebSocketConnection()
        state.withLock { $0.connections.append(connection) }
        return connection
    }
}

final class ScriptedWebSocketConnection: WebSocketTransportConnection {
    enum PingBehavior: Sendable {
        /// Pong arrives immediately.
        case succeed
        /// Ping never completes (until the caller's timeout cancels it).
        case hang
        /// Ping fails immediately.
        case fail
    }

    private struct State {
        var sentMessages: [String] = []
        var sendError: Error?
        var pingBehavior: PingBehavior = .succeed
        var pingCount = 0
        var hangingPings: [UUID: CheckedContinuation<Void, Error>] = [:]
        var closed = false
    }

    let events: AsyncThrowingStream<WebSocketTransportEvent, Error>
    private let continuation: AsyncThrowingStream<WebSocketTransportEvent, Error>.Continuation
    private let state = Mutex(State())

    init() {
        let (stream, continuation) = AsyncThrowingStream<WebSocketTransportEvent, Error>.makeStream()
        self.events = stream
        self.continuation = continuation
    }

    // MARK: - Test inspection

    var sentMessages: [String] {
        state.withLock { $0.sentMessages }
    }

    var isClosed: Bool {
        state.withLock { $0.closed }
    }

    var pingCount: Int {
        state.withLock { $0.pingCount }
    }

    func sentMessages(action: String) -> [String] {
        sentMessages.filter { $0.contains("\"action\":\"\(action)\"") }
    }

    // MARK: - Test scripting

    func setPingBehavior(_ behavior: PingBehavior) {
        state.withLock { $0.pingBehavior = behavior }
    }

    func setSendError(_ error: Error?) {
        state.withLock { $0.sendError = error }
    }

    func scriptOpened() {
        continuation.yield(.opened)
    }

    func scriptText(_ text: String) {
        continuation.yield(.text(text))
    }

    func scriptClosed(code: Int? = nil, reason: String? = nil) {
        continuation.yield(.closed(code: code, reason: reason))
        continuation.finish()
    }

    func scriptFailure(_ message: String = "scripted failure") {
        continuation.finish(throwing: ScriptedTransportError.scriptedFailure(message))
    }

    // MARK: - WebSocketTransportConnection

    func send(text: String) async throws {
        try state.withLock { state in
            if let error = state.sendError {
                throw error
            }
            state.sentMessages.append(text)
        }
    }

    func sendPing() async throws {
        let behavior: PingBehavior = state.withLock { state in
            state.pingCount += 1
            return state.pingBehavior
        }
        switch behavior {
        case .succeed:
            return
        case .fail:
            throw ScriptedTransportError.pingFailed
        case .hang:
            let id = UUID()
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    state.withLock { $0.hangingPings[id] = continuation }
                }
            } onCancel: {
                let continuation: CheckedContinuation<Void, Error>? = state.withLock {
                    $0.hangingPings.removeValue(forKey: id)
                }
                continuation?.resume(throwing: CancellationError())
            }
        }
    }

    func close() {
        let pending: [CheckedContinuation<Void, Error>] = state.withLock { state in
            state.closed = true
            let hanging = Array(state.hangingPings.values)
            state.hangingPings = [:]
            return hanging
        }
        for continuation in pending {
            continuation.resume(throwing: CancellationError())
        }
        continuation.finish()
    }
}
