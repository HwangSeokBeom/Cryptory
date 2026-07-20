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
/// state: one `opened`, one consumable terminal close/error, plus at most one
/// text frame (the documented canceled-waiter slot). The terminal result is
/// distinct from the permanent `ended` state, so consuming it cannot reopen
/// the connection. First terminal wins: explicit `close()` establishes ended
/// state only when it is itself the first terminal transition and never
/// erases an already accepted terminal result, which stays consumable by
/// exactly one `receive()`. No repository-owned queue of raw frames can form.
/// Foundation/network-stack internal buffering is
/// opaque and outside this bound; producer pressure beyond it stays in the
/// network/kernel buffers under TCP flow control.
///
/// **`@unchecked Sendable` boundary (documented):** the connection is shared
/// between the engine actor, URLSession's delegate/completion queues, and
/// cancellation handlers. All mutable state lives in `Shared` and is only
/// accessed through `SharedBox`'s mutex; continuations extracted under the
/// lock are resumed exactly once outside it. The remaining stored properties
/// are immutable references/closures (`shared`, `driver`, `session`,
/// `delegate`, `beforeReceiveWaiterInstall`) assigned in `init`. The
/// declaration is `@unchecked` only because
/// `URLSessionWebSocketTask` (the production driver) and `URLSession` are
/// not `Sendable`; both are thread-safe by Foundation's contract and are
/// only used through their documented concurrent-safe APIs.
final class URLSessionWebSocketTransportConnection: WebSocketTransportConnection, @unchecked Sendable {
    private enum TerminalResult {
        case event(WebSocketTransportEvent)
        case failure(Error)
    }

    private struct Shared {
        /// Non-terminal control events awaiting delivery: at most one
        /// `.opened` per connection lifetime — bounded by construction.
        var pendingControl: [WebSocketTransportEvent] = []
        /// At most one frame, kept only if a completed receive lost its
        /// waiter to cancellation (the single documented canceled-waiter
        /// slot).
        var pendingText: String?
        /// The first delegate/driver terminal result is consumable once. The
        /// separate permanent `ended` bit remains true after it is consumed.
        var pendingTerminal: TerminalResult?
        var ended = false
        var waiter: (id: UUID, continuation: CheckedContinuation<WebSocketTransportEvent, Error>)?
        var receiveInFlight = false
        var closeRequested = false
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

        /// Delivers a delegate-reported control event. The first close marks
        /// the connection ended immediately and is either delivered to the
        /// waiter or retained as the single consumable terminal result.
        func deliverControlEvent(_ event: WebSocketTransportEvent) {
            let continuation: CheckedContinuation<WebSocketTransportEvent, Error>? = withLock { state in
                switch event {
                case .closed:
                    guard !state.ended else { return nil }
                    state.ended = true
                    state.pendingControl.removeAll(keepingCapacity: false)
                    state.pendingText = nil
                    if let waiter = state.waiter {
                        state.waiter = nil
                        return waiter.continuation
                    }
                    state.pendingTerminal = .event(event)
                    return nil
                case .opened, .text:
                    guard !state.ended else { return nil }
                    if let waiter = state.waiter {
                        state.waiter = nil
                        return waiter.continuation
                    }
                    if case .opened = event,
                       state.pendingControl.contains(where: {
                           if case .opened = $0 { return true }
                           return false
                       }) {
                        return nil
                    }
                    state.pendingControl.append(event)
                    return nil
                }
            }
            continuation?.resume(returning: event)
        }

        /// Task completion: fails the pending waiter once, or records the
        /// terminal error for the next `receive()`. A late completion after
        /// the connection ended (or a duplicate completion) is a no-op and
        /// can never resume a continuation twice.
        func completeTask(error: Error?) {
            let continuation: CheckedContinuation<WebSocketTransportEvent, Error>? = withLock { state in
                guard !state.ended else { return nil }
                state.ended = true
                state.pendingControl.removeAll(keepingCapacity: false)
                state.pendingText = nil
                if let waiter = state.waiter {
                    state.waiter = nil
                    return waiter.continuation
                }
                if let error {
                    state.pendingTerminal = .failure(error)
                } else {
                    state.pendingTerminal = .failure(WebSocketTransportError.ended)
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
    private let beforeReceiveWaiterInstall: (@Sendable () -> Void)?

    init(url: URL, configuration: URLSessionConfiguration) {
        let shared = SharedBox()
        self.shared = shared
        self.beforeReceiveWaiterInstall = nil

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
    init(
        driver: any WebSocketSocketDriver,
        beforeReceiveWaiterInstall: (@Sendable () -> Void)? = nil
    ) {
        self.shared = SharedBox()
        self.driver = driver
        self.session = nil
        self.delegate = nil
        self.beforeReceiveWaiterInstall = beforeReceiveWaiterInstall
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
                beforeReceiveWaiterInstall?()
                let action: Action = shared.withLock { state in
                    // Cancel-before-install closes the gap where onCancel ran
                    // before a waiter existed and therefore found nothing to
                    // remove. Checked first, under the same mutex that owns
                    // the slot, so a cancelled receive can never consume
                    // mailbox state — in particular it cannot swallow the
                    // single consumable terminal result.
                    guard !Task.isCancelled else {
                        return .fail(CancellationError())
                    }
                    if !state.pendingControl.isEmpty {
                        let event = state.pendingControl.removeFirst()
                        return .resume(event)
                    }
                    if let text = state.pendingText {
                        state.pendingText = nil
                        return .resume(.text(text))
                    }
                    if let terminal = state.pendingTerminal {
                        state.pendingTerminal = nil
                        switch terminal {
                        case .event(let event):
                            return .resume(event)
                        case .failure(let error):
                            return .fail(error)
                        }
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
                    guard !state.ended else { return nil }
                    state.ended = true
                    state.pendingControl.removeAll(keepingCapacity: false)
                    state.pendingText = nil
                    if let waiter = state.waiter {
                        state.waiter = nil
                        return (waiter.continuation, .failure(error))
                    }
                    state.pendingTerminal = .failure(error)
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
        let closeAction: (CheckedContinuation<WebSocketTransportEvent, Error>?, Bool) = shared.withLock { state in
            guard !state.closeRequested else { return (nil, false) }
            state.closeRequested = true
            if !state.ended {
                // Explicit close is itself the first terminal transition:
                // establish permanent ended state with no consumable terminal
                // result (later receives fail as ended).
                state.ended = true
                state.pendingControl.removeAll(keepingCapacity: false)
                state.pendingText = nil
            }
            // When a delegate close or driver error was already accepted,
            // first-terminal-wins: the stored pendingTerminal stays consumable
            // and is cleared only by the receive() that consumes it. Explicit
            // close must never erase it. (An accepted terminal cannot coexist
            // with a parked waiter, so the extraction below is a no-op then.)
            let waiter = state.waiter
            state.waiter = nil
            return (waiter?.continuation, true)
        }
        closeAction.0?.resume(throwing: CancellationError())
        guard closeAction.1 else { return }
        driver.cancel(with: .goingAway, reason: nil)
        session?.finishTasksAndInvalidate()
    }

    struct DebugReceiveState: Equatable {
        let pendingControlCount: Int
        let hasPendingText: Bool
        let hasPendingTerminal: Bool
        let ended: Bool
        let hasWaiter: Bool
        let receiveInFlight: Bool
    }

    var debugReceiveState: DebugReceiveState {
        shared.withLock { state in
            DebugReceiveState(
                pendingControlCount: state.pendingControl.count,
                hasPendingText: state.pendingText != nil,
                hasPendingTerminal: state.pendingTerminal != nil,
                ended: state.ended,
                hasWaiter: state.waiter != nil,
                receiveInFlight: state.receiveInFlight
            )
        }
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
