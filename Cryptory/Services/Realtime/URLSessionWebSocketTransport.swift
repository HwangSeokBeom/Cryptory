import Foundation

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

/// Compatibility boundary around URLSession types: all stored properties are
/// immutable and the continuation is thread-safe by contract, but
/// `URLSessionWebSocketTask` itself is not `Sendable`, so this wrapper carries
/// the only `@unchecked Sendable` in the new realtime path (documented in
/// Docs/REALTIME_PIPELINE.md).
final class URLSessionWebSocketTransportConnection: WebSocketTransportConnection, @unchecked Sendable {
    let events: AsyncThrowingStream<WebSocketTransportEvent, Error>

    private let task: URLSessionWebSocketTask
    private let session: URLSession
    private let delegate: SocketDelegate

    init(url: URL, configuration: URLSessionConfiguration) {
        let (stream, continuation) = AsyncThrowingStream<WebSocketTransportEvent, Error>.makeStream()
        self.events = stream

        let delegate = SocketDelegate(continuation: continuation)
        self.delegate = delegate

        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        self.session = session

        let task = session.webSocketTask(with: url)
        self.task = task

        Self.receiveLoop(task: task, continuation: continuation)
        task.resume()
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
        task.cancel(with: .goingAway, reason: nil)
        session.finishTasksAndInvalidate()
    }

    private static func receiveLoop(
        task: URLSessionWebSocketTask,
        continuation: AsyncThrowingStream<WebSocketTransportEvent, Error>.Continuation
    ) {
        task.receive { result in
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    continuation.yield(.text(text))
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        continuation.yield(.text(text))
                    }
                @unknown default:
                    break
                }
                receiveLoop(task: task, continuation: continuation)

            case .failure(let error):
                continuation.finish(throwing: error)
            }
        }
    }

    private final class SocketDelegate: NSObject, URLSessionWebSocketDelegate {
        private let continuation: AsyncThrowingStream<WebSocketTransportEvent, Error>.Continuation

        init(continuation: AsyncThrowingStream<WebSocketTransportEvent, Error>.Continuation) {
            self.continuation = continuation
        }

        func urlSession(
            _ session: URLSession,
            webSocketTask: URLSessionWebSocketTask,
            didOpenWithProtocol protocol: String?
        ) {
            continuation.yield(.opened)
        }

        func urlSession(
            _ session: URLSession,
            webSocketTask: URLSessionWebSocketTask,
            didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
            reason: Data?
        ) {
            let reasonText = reason.flatMap { String(data: $0, encoding: .utf8) }
            continuation.yield(.closed(code: closeCode.rawValue, reason: reasonText))
            continuation.finish()
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            if let error {
                continuation.finish(throwing: error)
            } else {
                continuation.finish()
            }
        }
    }
}
