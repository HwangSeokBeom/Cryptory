import Foundation
import Synchronization

/// Production transport backed by `URLSessionWebSocketTask`.
///
/// Each `open(url:)` creates a dedicated `URLSession` whose delegate reports
/// socket open/close, so the engine gets a real `.opened` signal instead of
/// inferring liveness from the first received message.
struct URLSessionWebSocketTransport: WebSocketTransport {
    private let configuration: URLSessionConfiguration

    init(configuration: URLSessionConfiguration = .default) {
        self.configuration = configuration
    }

    func open(url: URL) -> any WebSocketTransportConnection {
        URLSessionWebSocketTransportConnection(url: url, configuration: configuration)
    }
}

/// Pull-based connection: exactly one `URLSessionWebSocketTask.receive` is
/// outstanding at a time, and it is only started when the engine calls
/// `receive()`. The mailbox below holds at most a fixed handful of control
/// events (`opened`, `closed`, one terminal error) plus at most one text
/// frame, so no unbounded pre-decode queue can form in the app; producer
/// pressure stays in the network/kernel buffers under TCP flow control.
///
/// Compatibility boundary around URLSession types: shared state is guarded
/// by a `Mutex`, but `URLSessionWebSocketTask` itself is not `Sendable`, so
/// this wrapper carries the only `@unchecked Sendable` in the new realtime
/// path (documented in Docs/REALTIME_PIPELINE.md).
final class URLSessionWebSocketTransportConnection: WebSocketTransportConnection, @unchecked Sendable {
    private struct Shared {
        /// Control events awaiting delivery: at most one `.opened` and one
        /// `.closed` per connection lifetime — bounded by construction.
        var pendingControl: [WebSocketTransportEvent] = []
        /// At most one frame, kept only if a completed receive lost its
        /// waiter to cancellation.
        var pendingText: String?
        var terminalError: Error?
        var ended = false
        var waiter: (id: UUID, continuation: CheckedContinuation<WebSocketTransportEvent, Error>)?
        var receiveInFlight = false
    }

    /// Reference box so the connection and its session delegate can share the
    /// same mutex (`Mutex` itself is noncopyable).
    private final class SharedBox: @unchecked Sendable {
        let mutex = Mutex(Shared())

        func withLock<R>(_ body: (inout Shared) -> sending R) -> sending R {
            mutex.withLock(body)
        }
    }

    private let shared: SharedBox
    private let task: URLSessionWebSocketTask
    private let session: URLSession
    private let delegate: SocketDelegate

    init(url: URL, configuration: URLSessionConfiguration) {
        let shared = SharedBox()
        self.shared = shared

        let delegate = SocketDelegate(shared: shared)
        self.delegate = delegate

        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        self.session = session

        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()
    }

    func receive() async throws -> WebSocketTransportEvent {
        let waiterID = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<WebSocketTransportEvent, Error>) in
                enum Action {
                    case resume(WebSocketTransportEvent)
                    case fail(Error)
                    case startReceive
                    case wait
                }
                let action: Action = shared.withLock { state in
                    if !state.pendingControl.isEmpty {
                        let event = state.pendingControl.removeFirst()
                        if case .closed = event { state.ended = true }
                        return .resume(event)
                    }
                    if let text = state.pendingText {
                        state.pendingText = nil
                        return .resume(.text(text))
                    }
                    if let error = state.terminalError {
                        state.terminalError = nil
                        state.ended = true
                        return .fail(error)
                    }
                    if state.ended {
                        return .fail(WebSocketTransportError.ended)
                    }
                    // Single-caller contract: a second concurrent waiter is a
                    // programming error; end it deterministically instead of
                    // silently dropping either continuation.
                    guard state.waiter == nil else {
                        return .fail(WebSocketTransportError.ended)
                    }
                    state.waiter = (waiterID, continuation)
                    if state.receiveInFlight {
                        return .wait
                    }
                    state.receiveInFlight = true
                    return .startReceive
                }
                switch action {
                case .resume(let event):
                    continuation.resume(returning: event)
                case .fail(let error):
                    continuation.resume(throwing: error)
                case .startReceive:
                    startReceive()
                case .wait:
                    break
                }
            }
        } onCancel: {
            let continuation: CheckedContinuation<WebSocketTransportEvent, Error>? = shared.withLock { state in
                guard state.waiter?.id == waiterID else { return nil }
                let waiter = state.waiter
                state.waiter = nil
                return waiter?.continuation
            }
            continuation?.resume(throwing: CancellationError())
        }
    }

    /// Starts exactly one `URLSessionWebSocketTask.receive`. The next one is
    /// only started by the next engine `receive()` call, after the current
    /// frame has been accepted — this is what bounds pre-decode memory.
    private func startReceive() {
        task.receive { [shared] result in
            let resumption: (CheckedContinuation<WebSocketTransportEvent, Error>, Result<WebSocketTransportEvent, Error>)? = shared.withLock { state in
                state.receiveInFlight = false
                switch result {
                case .success(let message):
                    let text: String?
                    switch message {
                    case .string(let string):
                        text = string
                    case .data(let data):
                        text = String(data: data, encoding: .utf8)
                    @unknown default:
                        text = nil
                    }
                    guard let text else { return nil }
                    if let waiter = state.waiter {
                        state.waiter = nil
                        return (waiter.continuation, .success(.text(text)))
                    }
                    state.pendingText = text
                    return nil
                case .failure(let error):
                    if let waiter = state.waiter {
                        state.waiter = nil
                        state.ended = true
                        return (waiter.continuation, .failure(error))
                    }
                    state.terminalError = error
                    return nil
                }
            }
            if let (continuation, result) = resumption {
                continuation.resume(with: result)
            } else if case .success = result {
                // A non-text frame with no pending text: ask for the next
                // frame on behalf of the still-waiting caller, if any.
                let shouldContinue: Bool = shared.withLock { state in
                    guard state.waiter != nil, state.pendingText == nil, !state.ended else { return false }
                    state.receiveInFlight = true
                    return true
                }
                if shouldContinue {
                    self.startReceive()
                }
            }
        }
    }

    func send(text: String) async throws {
        try await task.send(.string(text))
    }

    func sendPing() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            task.sendPing { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func close() {
        let continuation: CheckedContinuation<WebSocketTransportEvent, Error>? = shared.withLock { state in
            state.ended = true
            let waiter = state.waiter
            state.waiter = nil
            return waiter?.continuation
        }
        continuation?.resume(throwing: CancellationError())
        task.cancel(with: .goingAway, reason: nil)
        session.finishTasksAndInvalidate()
    }

    private final class SocketDelegate: NSObject, URLSessionWebSocketDelegate {
        private let shared: SharedBox

        init(shared: SharedBox) {
            self.shared = shared
        }

        private func deliver(_ event: WebSocketTransportEvent) {
            let continuation: CheckedContinuation<WebSocketTransportEvent, Error>? = shared.withLock { state in
                guard !state.ended else { return nil }
                if let waiter = state.waiter {
                    state.waiter = nil
                    if case .closed = event { state.ended = true }
                    return waiter.continuation
                }
                state.pendingControl.append(event)
                return nil
            }
            continuation?.resume(returning: event)
        }

        func urlSession(
            _ session: URLSession,
            webSocketTask: URLSessionWebSocketTask,
            didOpenWithProtocol protocol: String?
        ) {
            deliver(.opened)
        }

        func urlSession(
            _ session: URLSession,
            webSocketTask: URLSessionWebSocketTask,
            didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
            reason: Data?
        ) {
            let reasonText = reason.flatMap { String(data: $0, encoding: .utf8) }
            deliver(.closed(code: closeCode.rawValue, reason: reasonText))
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            let continuation: CheckedContinuation<WebSocketTransportEvent, Error>? = shared.withLock { state in
                if let waiter = state.waiter {
                    state.waiter = nil
                    state.ended = true
                    return waiter.continuation
                }
                guard !state.ended else { return nil }
                if let error {
                    state.terminalError = error
                } else {
                    state.ended = true
                }
                return nil
            }
            continuation?.resume(throwing: error ?? WebSocketTransportError.ended)
        }
    }
}
