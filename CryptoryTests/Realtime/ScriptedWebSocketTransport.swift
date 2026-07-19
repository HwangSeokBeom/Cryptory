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
        var suspendSendsOnOpen = false
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

    /// New connections start with their send gate closed, so the very first
    /// outbound message suspends deterministically (no race between opening
    /// the connection and arming the gate).
    func setSuspendSendsOnOpen(_ enabled: Bool) {
        state.withLock { $0.suspendSendsOnOpen = enabled }
    }

    func open(url: URL) -> any WebSocketTransportConnection {
        let connection = ScriptedWebSocketConnection()
        let gated: Bool = state.withLock { state in
            state.connections.append(connection)
            return state.suspendSendsOnOpen
        }
        if gated {
            connection.beginSuspendingSends()
        }
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

    private struct SuspendedSend {
        let id: UUID
        let message: String
        let continuation: CheckedContinuation<Void, Error>
    }

    private struct State {
        var sentMessages: [String] = []
        var sendError: Error?
        var pingBehavior: PingBehavior = .succeed
        var pingCount = 0
        var hangingPings: [UUID: CheckedContinuation<Void, Error>] = [:]
        var closed = false
        /// While true, `send(text:)` suspends instead of completing. Suspended
        /// sends ignore task cancellation by default (modeling URLSession,
        /// which may resume a send after cancellation) so stale-sender
        /// interleavings can be scripted deterministically.
        var suspendingSends = false
        var respectsSendCancellation = false
        var suspendedSends: [SuspendedSend] = []
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

    // MARK: - Send gate scripting

    var suspendedSendCount: Int {
        state.withLock { $0.suspendedSends.count }
    }

    var suspendedSendMessages: [String] {
        state.withLock { $0.suspendedSends.map(\.message) }
    }

    /// Every subsequent `send(text:)` suspends until resumed or failed.
    /// With `respectingCancellation: false` (default) a suspended send stays
    /// suspended across task cancellation — required for stale-sender tests.
    func beginSuspendingSends(respectingCancellation: Bool = false) {
        state.withLock {
            $0.suspendingSends = true
            $0.respectsSendCancellation = respectingCancellation
        }
    }

    /// Resumes all currently suspended sends as successes (recording their
    /// messages in arrival order). Reopens the gate by default.
    func resumeSuspendedSends(reopenGate: Bool = true) {
        let resumable: [SuspendedSend] = state.withLock { state in
            if reopenGate { state.suspendingSends = false }
            let pending = state.suspendedSends
            state.suspendedSends = []
            state.sentMessages.append(contentsOf: pending.map(\.message))
            return pending
        }
        for send in resumable {
            send.continuation.resume()
        }
    }

    /// Resumes all currently suspended sends by throwing. Messages are not
    /// recorded as sent. Reopens the gate by default.
    func failSuspendedSends(
        _ error: Error = ScriptedTransportError.scriptedFailure("suspended send failed"),
        reopenGate: Bool = true
    ) {
        let resumable: [SuspendedSend] = state.withLock { state in
            if reopenGate { state.suspendingSends = false }
            let pending = state.suspendedSends
            state.suspendedSends = []
            return pending
        }
        for send in resumable {
            send.continuation.resume(throwing: error)
        }
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
        enum Disposition {
            case complete
            case fail(Error)
            case suspend(UUID, Bool)
        }
        let id = UUID()
        let disposition: Disposition = state.withLock { state in
            if let error = state.sendError {
                return .fail(error)
            }
            if state.suspendingSends {
                return .suspend(id, state.respectsSendCancellation)
            }
            state.sentMessages.append(text)
            return .complete
        }
        switch disposition {
        case .complete:
            return
        case .fail(let error):
            throw error
        case .suspend(let id, let respectsCancellation):
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    state.withLock {
                        $0.suspendedSends.append(
                            SuspendedSend(id: id, message: text, continuation: continuation)
                        )
                    }
                }
            } onCancel: {
                guard respectsCancellation else { return }
                let continuation: CheckedContinuation<Void, Error>? = state.withLock { state in
                    guard let index = state.suspendedSends.firstIndex(where: { $0.id == id }) else {
                        return nil
                    }
                    return state.suspendedSends.remove(at: index).continuation
                }
                continuation?.resume(throwing: CancellationError())
            }
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
