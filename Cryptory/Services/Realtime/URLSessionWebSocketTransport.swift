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

/// Narrow internal seam over the socket task so the production connection's
/// receive/cancel/close state machine can be driven deterministically in
/// tests. The production driver is `URLSessionWebSocketTask` itself; tests
/// inject a controllable implementation. Delegate-reported socket events
/// (`opened` / `closed` / task completion) enter through the connection's
/// internal `handleSocket*` methods, which the production `SocketDelegate`
/// and tests share.
///
/// Not `Sendable` by design: `URLSessionWebSocketTask` is not `Sendable`, so
/// the driver reference lives inside the connection's documented
/// `@unchecked Sendable` boundary.
protocol WebSocketSocketDriver: AnyObject {
    func resume()
    func receive(completionHandler: @escaping @Sendable (Result<URLSessionWebSocketTask.Message, any Error>) -> Void)
    func send(_ message: URLSessionWebSocketTask.Message) async throws
    func sendPing(pongReceiveHandler: @escaping @Sendable ((any Error)?) -> Void)
    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?)
}

extension URLSessionWebSocketTask: WebSocketSocketDriver {}

/// Pull-based connection: exactly one repository-level `receive` is
/// outstanding at a time, and it is only started when the engine calls
/// `receive()`. The mailbox below holds at most a fixed handful of control
/// events (`opened`, `closed`, one terminal error) plus at most one text
/// frame (the documented canceled-waiter slot), so no repository-owned queue
/// of raw frames can form. Foundation/network-stack internal buffering is
/// opaque and outside this bound; producer pressure beyond it stays in the
/// network/kernel buffers under TCP flow control.
///
/// **`@unchecked Sendable` boundary (documented):** the connection is shared
/// between the engine actor, URLSession's delegate/completion queues, and
/// cancellation handlers. All mutable state lives in `Shared` and is only
/// accessed through `SharedBox`'s mutex; continuations extracted under the
/// lock are resumed exactly once outside it. The remaining stored properties
/// are immutable references (`shared`, `driver`, `session`, `delegate`)
/// assigned in `init`. The declaration is `@unchecked` only because
/// `URLSessionWebSocketTask` (the production driver) and `URLSession` are
/// not `Sendable`; both are thread-safe by Foundation's contract and are
/// only used through their documented concurrent-safe APIs.
final class URLSessionWebSocketTransportConnection: WebSocketTransportConnection, @unchecked Sendable {
    private struct Shared {
        /// Control events awaiting delivery: at most one `.opened` and one
        /// `.closed` per connection lifetime — bounded by construction.
        var pendingControl: [WebSocketTransportEvent] = []
        /// At most one frame, kept only if a completed receive lost its
        /// waiter to cancellation (the single documented canceled-waiter
        /// slot).
        var pendingText: String?
        var terminalError: Error?
        var ended = false
        var waiter: (id: UUID, continuation: CheckedContinuation<WebSocketTransportEvent, Error>)?
        var receiveInFlight = false
    }

    /// Reference box so the connection and its session delegate share the
    /// same mutex (`Mutex` itself is noncopyable). Checked `Sendable`: its
    /// only stored property is the `Mutex`, which is `Sendable` by the
    /// standard library's contract; every access to the protected `Shared`
    /// state goes through `withLock`.
    private final class SharedBox: Sendable {
        let mutex = Mutex(Shared())

        func withLock<R>(_ body: (inout Shared) -> sending R) -> sending R {
            mutex.withLock(body)
        }

        /// Delivers a delegate-reported control event: resumes the pending
        /// waiter if one exists, otherwise appends to the bounded control
        /// mailbox. No-op after the connection ended.
        func deliverControlEvent(_ event: WebSocketTransportEvent) {
            let continuation: CheckedContinuation<WebSocketTransportEvent, Error>? = withLock { state in
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

        /// Task completion: fails the pending waiter once, or records the
        /// terminal error for the next `receive()`. A late completion after
        /// the connection ended (or a duplicate completion) is a no-op and
        /// can never resume a continuation twice.
        func completeTask(error: Error?) {
            let continuation: CheckedContinuation<WebSocketTransportEvent, Error>? = withLock { state in
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

    private let shared: SharedBox
    private let driver: any WebSocketSocketDriver
    private let session: URLSession?
    private let delegate: SocketDelegate?

    init(url: URL, configuration: URLSessionConfiguration) {
        let shared = SharedBox()
        self.shared = shared

        let delegate = SocketDelegate(shared: shared)
        self.delegate = delegate

        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        self.session = session

        let task = session.webSocketTask(with: url)
        self.driver = task
        task.resume()
    }

    /// Test seam: drives the identical state machine through an injected
    /// driver; socket lifecycle events are injected via `handleSocket*`.
    init(driver: any WebSocketSocketDriver) {
        self.shared = SharedBox()
        self.driver = driver
        self.session = nil
        self.delegate = nil
        driver.resume()
    }

    // MARK: - Socket lifecycle events (delegate-reported or test-injected)

    func handleSocketOpened() {
        shared.deliverControlEvent(.opened)
    }

    func handleSocketClosed(code: Int?, reason: String?) {
        shared.deliverControlEvent(.closed(code: code, reason: reason))
    }

    func handleTaskCompleted(error: Error?) {
        shared.completeTask(error: error)
    }

    // MARK: - WebSocketTransportConnection

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

    /// Starts exactly one driver-level receive. The next one is only started
    /// by the next engine `receive()` call, after the current frame has been
    /// accepted — this is what bounds repository-owned pre-decode memory.
    private func startReceive() {
        driver.receive { [shared] result in
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
                    guard !state.ended else { return nil }
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
                    guard !state.ended else { return nil }
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
        try await driver.send(.string(text))
    }

    func sendPing() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            driver.sendPing { error in
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
        driver.cancel(with: .goingAway, reason: nil)
        session?.finishTasksAndInvalidate()
    }

    private final class SocketDelegate: NSObject, URLSessionWebSocketDelegate {
        private let shared: SharedBox

        init(shared: SharedBox) {
            self.shared = shared
        }

        func urlSession(
            _ session: URLSession,
            webSocketTask: URLSessionWebSocketTask,
            didOpenWithProtocol protocol: String?
        ) {
            shared.deliverControlEvent(.opened)
        }

        func urlSession(
            _ session: URLSession,
            webSocketTask: URLSessionWebSocketTask,
            didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
            reason: Data?
        ) {
            let reasonText = reason.flatMap { String(data: $0, encoding: .utf8) }
            shared.deliverControlEvent(.closed(code: closeCode.rawValue, reason: reasonText))
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            shared.completeTask(error: error)
        }
    }
}
