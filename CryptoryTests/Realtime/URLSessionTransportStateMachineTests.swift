import XCTest
@testable import Cryptory

/// Deterministic driver test double for the production
/// `URLSessionWebSocketTransportConnection`: records every driver call and
/// hands the stored completion handlers to the test, so late, duplicate, and
/// post-disconnect completions can be scripted exactly. Thread-safe via a
/// lock (driver callbacks arrive from arbitrary queues in production).
private final class ControlledSocketDriver: WebSocketSocketDriver, @unchecked Sendable {
    typealias ReceiveCompletion = @Sendable (Result<URLSessionWebSocketTask.Message, any Error>) -> Void
    typealias PingCompletion = @Sendable ((any Error)?) -> Void

    private let lock = NSLock()
    private var receiveCompletions: [ReceiveCompletion] = []
    private var pingCompletions: [PingCompletion] = []
    private var recordedSends: [String] = []
    private var resumeCallCount = 0
    private var cancelCallCount = 0
    private var totalReceiveCallCount = 0

    var resumeCount: Int {
        lock.lock(); defer { lock.unlock() }
        return resumeCallCount
    }

    var cancelCount: Int {
        lock.lock(); defer { lock.unlock() }
        return cancelCallCount
    }

    /// Total driver-level receive calls ever made by the connection.
    var receiveCallCount: Int {
        lock.lock(); defer { lock.unlock() }
        return totalReceiveCallCount
    }

    /// Driver receive calls whose completion has not been invoked yet.
    var pendingReceiveCount: Int {
        lock.lock(); defer { lock.unlock() }
        return receiveCompletions.count
    }

    var sentTexts: [String] {
        lock.lock(); defer { lock.unlock() }
        return recordedSends
    }

    var pendingPingCount: Int {
        lock.lock(); defer { lock.unlock() }
        return pingCompletions.count
    }

    func resume() {
        lock.lock(); defer { lock.unlock() }
        resumeCallCount += 1
    }

    func receive(completionHandler: @escaping ReceiveCompletion) {
        lock.lock(); defer { lock.unlock() }
        totalReceiveCallCount += 1
        receiveCompletions.append(completionHandler)
    }

    func send(_ message: URLSessionWebSocketTask.Message) async throws {
        if case .string(let text) = message {
            recordSend(text)
        }
    }

    private func recordSend(_ text: String) {
        lock.lock()
        recordedSends.append(text)
        lock.unlock()
    }

    func sendPing(pongReceiveHandler: @escaping PingCompletion) {
        lock.lock()
        pingCompletions.append(pongReceiveHandler)
        lock.unlock()
    }

    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        lock.lock(); defer { lock.unlock() }
        cancelCallCount += 1
    }

    /// Removes and returns the oldest stored receive completion so the test
    /// can invoke it at a scripted point (late, after close, or twice).
    func takeReceiveCompletion() -> ReceiveCompletion? {
        lock.lock(); defer { lock.unlock() }
        guard !receiveCompletions.isEmpty else { return nil }
        return receiveCompletions.removeFirst()
    }

    func takePingCompletion() -> PingCompletion? {
        lock.lock(); defer { lock.unlock() }
        guard !pingCompletions.isEmpty else { return nil }
        return pingCompletions.removeFirst()
    }
}

private enum DriverTestError: Error {
    case scripted
}

/// Synchronous one-shot gate used only at the production wrapper's
/// pre-install seam. It blocks the receive task without sleeps while the test
/// cancels it, then remains open for subsequent receives.
private final class ReceiveInstallGate: @unchecked Sendable {
    private let condition = NSCondition()
    private var entered = false
    private var open = false

    var hasEntered: Bool {
        condition.lock(); defer { condition.unlock() }
        return entered
    }

    func wait() {
        condition.lock()
        entered = true
        condition.broadcast()
        while !open {
            condition.wait()
        }
        condition.unlock()
    }

    func release() {
        condition.lock()
        open = true
        condition.broadcast()
        condition.unlock()
    }
}

/// Direct, deterministic tests for the production transport wrapper's state
/// machine (`URLSessionWebSocketTransportConnection`), exercised through the
/// injected `WebSocketSocketDriver` seam and the internal `handleSocket*`
/// lifecycle entry points shared with the URLSession delegate. Continuation
/// gates and scripted completions replace all timing assumptions; nothing
/// here claims control over Foundation-internal buffering.
final class URLSessionTransportStateMachineTests: XCTestCase {
    @discardableResult
    private func waitUntil(
        timeout: Duration = .seconds(30),
        _ condition: () async -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while !(await condition()) {
            if ContinuousClock.now >= deadline { return false }
            await Task.yield()
        }
        return true
    }

    private func settle(yields: Int = 500) async {
        for _ in 0..<yields {
            await Task.yield()
        }
    }

    private func makeConnection() -> (URLSessionWebSocketTransportConnection, ControlledSocketDriver) {
        let driver = ControlledSocketDriver()
        let connection = URLSessionWebSocketTransportConnection(driver: driver)
        return (connection, driver)
    }

    /// Starts `receive()` in a task that reports its outcome.
    private func startReceive(
        on connection: URLSessionWebSocketTransportConnection
    ) -> Task<Result<WebSocketTransportEvent, Error>, Never> {
        Task {
            do {
                return .success(try await connection.receive())
            } catch {
                return .failure(error)
            }
        }
    }

    // MARK: - One receive outstanding

    func testExactlyOneDriverReceiveIsOutstandingAtATime() async throws {
        let (connection, driver) = makeConnection()
        XCTAssertEqual(driver.resumeCount, 1, "the connection resumes its driver once on creation")

        let first = startReceive(on: connection)
        let started = await waitUntil { driver.receiveCallCount == 1 }
        XCTAssertTrue(started, "engine receive() starts exactly one driver receive")
        await settle()
        XCTAssertEqual(driver.receiveCallCount, 1, "no additional driver receive while one is outstanding")

        driver.takeReceiveCompletion()?(.success(.string("frame-1")))
        guard case .success(.text(let text)) = await first.value else {
            return XCTFail("first receive must deliver the completed frame")
        }
        XCTAssertEqual(text, "frame-1")

        // The next driver receive starts only on the next engine receive().
        XCTAssertEqual(driver.receiveCallCount, 1)
        let second = startReceive(on: connection)
        let secondStarted = await waitUntil { driver.receiveCallCount == 2 }
        XCTAssertTrue(secondStarted, "next frame is requested only on demand")
        driver.takeReceiveCompletion()?(.success(.string("frame-2")))
        guard case .success(.text(let secondText)) = await second.value else {
            return XCTFail("second receive must deliver the second frame")
        }
        XCTAssertEqual(secondText, "frame-2")
    }

    func testSecondConcurrentWaiterFailsDeterministicallyWithoutDroppingTheFirst() async throws {
        let (connection, driver) = makeConnection()
        let first = startReceive(on: connection)
        await waitUntil { driver.receiveCallCount == 1 }

        let second = startReceive(on: connection)
        guard case .failure(let error) = await second.value else {
            return XCTFail("a second concurrent waiter violates the single-caller contract and must fail")
        }
        XCTAssertTrue(error is WebSocketTransportError, "deterministic failure, got \(error)")

        driver.takeReceiveCompletion()?(.success(.string("frame")))
        guard case .success(.text(let text)) = await first.value else {
            return XCTFail("the original waiter must remain intact")
        }
        XCTAssertEqual(text, "frame")
    }

    // MARK: - Cancellation and the single canceled-waiter slot

    func testCancellingPendingReceiveReleasesItsWaiter() async throws {
        let (connection, driver) = makeConnection()
        let receive = startReceive(on: connection)
        await waitUntil { driver.receiveCallCount == 1 }

        receive.cancel()
        guard case .failure(let error) = await receive.value else {
            return XCTFail("cancellation must release the waiter by throwing")
        }
        XCTAssertTrue(error is CancellationError, "got \(error)")
    }

    func testCancelBeforeWaiterInstallDoesNotStartDriverAndNextReceiveWorks() async throws {
        let driver = ControlledSocketDriver()
        let gate = ReceiveInstallGate()
        let connection = URLSessionWebSocketTransportConnection(
            driver: driver,
            beforeReceiveWaiterInstall: { gate.wait() }
        )
        let cancelled = startReceive(on: connection)
        let entered = await waitUntil { gate.hasEntered }
        XCTAssertTrue(entered, "receive must enter the deterministic pre-install gate")

        cancelled.cancel()
        gate.release()
        guard case .failure(let error) = await cancelled.value else {
            return XCTFail("cancel-before-install must throw")
        }
        XCTAssertTrue(error is CancellationError, "got \(error)")
        XCTAssertEqual(driver.receiveCallCount, 0, "an already-cancelled receive must not start the driver")
        XCTAssertEqual(
            connection.debugReceiveState,
            .init(
                pendingControlCount: 0,
                hasPendingText: false,
                hasPendingTerminal: false,
                ended: false,
                hasWaiter: false,
                receiveInFlight: false
            ),
            "no waiter, canceled slot, or receive ownership may remain"
        )

        let next = startReceive(on: connection)
        let started = await waitUntil { driver.receiveCallCount == 1 }
        XCTAssertTrue(started, "a subsequent normal receive must acquire ownership")
        driver.takeReceiveCompletion()?(.success(.string("fresh")))
        guard case .success(.text(let text)) = await next.value else {
            return XCTFail("the subsequent normal receive must work")
        }
        XCTAssertEqual(text, "fresh")
    }

    func testLateCompletionAfterCancelFillsTheSingleDocumentedSlot() async throws {
        let (connection, driver) = makeConnection()
        let receive = startReceive(on: connection)
        await waitUntil { driver.receiveCallCount == 1 }
        receive.cancel()
        _ = await receive.value

        // The driver receive completes after its waiter was cancelled: the
        // frame lands in the single canceled-waiter slot instead of being
        // dropped or resuming a dead continuation.
        driver.takeReceiveCompletion()?(.success(.string("late-frame")))

        // The next receive drains the slot without a new driver receive…
        let next = startReceive(on: connection)
        guard case .success(.text(let text)) = await next.value else {
            return XCTFail("the slot frame must be delivered to the next receive")
        }
        XCTAssertEqual(text, "late-frame")
        XCTAssertEqual(driver.receiveCallCount, 1, "slot delivery must not start a new driver receive")

        // …and only then does a new engine receive start a new driver call.
        let following = startReceive(on: connection)
        let started = await waitUntil { driver.receiveCallCount == 2 }
        XCTAssertTrue(started)
        driver.takeReceiveCompletion()?(.success(.string("fresh")))
        guard case .success(.text(let fresh)) = await following.value else {
            return XCTFail("fresh frame must be delivered")
        }
        XCTAssertEqual(fresh, "fresh")
    }

    func testDuplicateDriverCompletionCannotDoubleResumeOrGrowTheMailbox() async throws {
        let (connection, driver) = makeConnection()
        let receive = startReceive(on: connection)
        await waitUntil { driver.receiveCallCount == 1 }
        let completion = try XCTUnwrap(driver.takeReceiveCompletion())

        // First invocation resumes the waiter…
        completion(.success(.string("first")))
        guard case .success(.text(let text)) = await receive.value else {
            return XCTFail("first completion must deliver")
        }
        XCTAssertEqual(text, "first")

        // …a duplicate invocation (impossible for a well-behaved driver, the
        // guarded case) must not resume anything twice and at most refills
        // the single bounded slot — no repository-owned queue can grow.
        completion(.success(.string("duplicate")))
        completion(.success(.string("duplicate-2")))
        let next = startReceive(on: connection)
        guard case .success(.text(let slotText)) = await next.value else {
            return XCTFail("the bounded slot delivers at most one frame")
        }
        XCTAssertEqual(slotText, "duplicate-2", "the slot holds at most the newest frame — bounded at one")
        // Nothing else is queued: the following receive suspends on a fresh
        // driver call rather than draining more stored frames.
        let following = startReceive(on: connection)
        let started = await waitUntil { driver.receiveCallCount == 2 }
        XCTAssertTrue(started, "no additional frames may be queued repository-side")
        following.cancel()
        _ = await following.value
    }

    // MARK: - Disconnect ownership

    func testCloseFailsPendingReceiveAndLateCompletionCannotResurrectIt() async throws {
        let (connection, driver) = makeConnection()
        let receive = startReceive(on: connection)
        await waitUntil { driver.receiveCallCount == 1 }

        connection.close()
        XCTAssertEqual(driver.cancelCount, 1)
        guard case .failure(let error) = await receive.value else {
            return XCTFail("close must fail the pending receive")
        }
        XCTAssertTrue(error is CancellationError, "got \(error)")

        // A late driver completion after disconnect is ownerless: it must
        // not park a frame that a post-close receive could observe.
        driver.takeReceiveCompletion()?(.success(.string("late-after-close")))
        let next = startReceive(on: connection)
        guard case .failure(let nextError) = await next.value else {
            return XCTFail("receive after close must throw, not deliver a stale frame")
        }
        XCTAssertTrue(nextError is WebSocketTransportError, "got \(nextError)")
    }

    func testLateCompletionFromOldConnectionCannotEnterNewConnection() async throws {
        let (oldConnection, oldDriver) = makeConnection()
        let oldReceive = startReceive(on: oldConnection)
        await waitUntil { oldDriver.receiveCallCount == 1 }
        oldConnection.close()
        _ = await oldReceive.value

        let (newConnection, newDriver) = makeConnection()
        let newReceive = startReceive(on: newConnection)
        await waitUntil { newDriver.receiveCallCount == 1 }

        // The old generation's driver completes late: the new connection's
        // pending receive must be untouched.
        oldDriver.takeReceiveCompletion()?(.success(.string("old-generation")))
        await settle()
        newDriver.takeReceiveCompletion()?(.success(.string("new-generation")))
        guard case .success(.text(let text)) = await newReceive.value else {
            return XCTFail("new connection must deliver its own frame")
        }
        XCTAssertEqual(text, "new-generation")
    }

    func testTaskCompletionAfterCloseIsANoOpAndCannotDoubleResume() async throws {
        let (connection, driver) = makeConnection()
        let receive = startReceive(on: connection)
        await waitUntil { driver.receiveCallCount == 1 }

        connection.close()
        _ = await receive.value

        // Delegate-reported task completion arriving after close (URLSession
        // does this) must not resume anything: the waiter was already
        // resumed by close, and the connection has ended.
        connection.handleTaskCompleted(error: DriverTestError.scripted)
        connection.handleTaskCompleted(error: nil)

        let next = startReceive(on: connection)
        guard case .failure(let error) = await next.value else {
            return XCTFail("the connection stays ended")
        }
        XCTAssertTrue(error is WebSocketTransportError, "got \(error)")
    }

    func testRepeatedCloseIsIdempotent() async {
        let (connection, driver) = makeConnection()
        connection.close()
        connection.close()
        connection.close()
        XCTAssertEqual(driver.cancelCount, 1, "close must cancel the driver at most once")

        let receive = startReceive(on: connection)
        guard case .failure = await receive.value else {
            return XCTFail("receive after close must throw")
        }
    }

    // MARK: - Delegate-reported lifecycle events

    func testSocketOpenAndCloseEventsFlowThroughTheBoundedControlMailbox() async throws {
        let (connection, driver) = makeConnection()

        // Events arriving before any receive() are parked in the bounded
        // control mailbox (at most one .opened and one .closed per lifetime).
        connection.handleSocketOpened()
        let first = startReceive(on: connection)
        guard case .success(.opened) = await first.value else {
            return XCTFail("parked .opened must be delivered first")
        }

        // A waiter present when the close arrives is resumed directly.
        let second = startReceive(on: connection)
        await waitUntil { driver.receiveCallCount == 1 }
        connection.handleSocketClosed(code: 1000, reason: "bye")
        guard case .success(.closed(let code, let reason)) = await second.value else {
            return XCTFail(".closed must resume the pending waiter")
        }
        XCTAssertEqual(code, 1000)
        XCTAssertEqual(reason, "bye")

        // After .closed the connection has ended.
        let third = startReceive(on: connection)
        guard case .failure(let error) = await third.value else {
            return XCTFail("receive after .closed must throw")
        }
        XCTAssertTrue(error is WebSocketTransportError, "got \(error)")
    }

    func testCloseWithoutWaiterQueuesOneTerminalEventThenStaysEnded() async {
        let (connection, _) = makeConnection()
        connection.handleSocketOpened()
        connection.handleSocketClosed(code: 1000, reason: "first")

        var state = connection.debugReceiveState
        XCTAssertTrue(state.ended, "accepting close marks the connection terminal immediately")
        XCTAssertEqual(state.pendingControlCount, 0, "terminal acceptance clears non-terminal control state")
        XCTAssertTrue(state.hasPendingTerminal, "one terminal event remains consumable")
        XCTAssertFalse(state.hasPendingText)
        XCTAssertFalse(state.hasWaiter)

        let first = startReceive(on: connection)
        guard case .success(.closed(let code, let reason)) = await first.value else {
            return XCTFail("the queued terminal close must be observable once")
        }
        XCTAssertEqual(code, 1000)
        XCTAssertEqual(reason, "first")

        state = connection.debugReceiveState
        XCTAssertTrue(state.ended, "consuming the event does not clear permanent terminal state")
        XCTAssertFalse(state.hasPendingTerminal)
        let second = startReceive(on: connection)
        guard case .failure(let error) = await second.value else {
            return XCTFail("all later receives must fail as ended")
        }
        XCTAssertTrue(error is WebSocketTransportError)
    }

    func testLateTextAndErrorAfterQueuedCloseCannotResurrectMailbox() async throws {
        let (connection, driver) = makeConnection()
        let pending = startReceive(on: connection)
        await waitUntil { driver.receiveCallCount == 1 }
        pending.cancel()
        _ = await pending.value

        connection.handleSocketClosed(code: 1001, reason: "terminal")
        let lateCompletion = try XCTUnwrap(driver.takeReceiveCompletion())
        lateCompletion(.success(.string("late-text")))
        connection.handleTaskCompleted(error: DriverTestError.scripted)

        let state = connection.debugReceiveState
        XCTAssertTrue(state.ended)
        XCTAssertFalse(state.hasPendingText, "late success cannot populate the canceled-waiter slot after terminal close")
        XCTAssertTrue(state.hasPendingTerminal, "late error cannot replace the accepted close")
        XCTAssertFalse(state.hasWaiter)
        XCTAssertFalse(state.receiveInFlight)
        XCTAssertEqual(state.pendingControlCount, 0)

        let terminal = startReceive(on: connection)
        guard case .success(.closed(let code, let reason)) = await terminal.value else {
            return XCTFail("the first accepted close must win")
        }
        XCTAssertEqual(code, 1001)
        XCTAssertEqual(reason, "terminal")
        let later = startReceive(on: connection)
        guard case .failure(let error) = await later.value else {
            return XCTFail("no text or second terminal result may follow close")
        }
        XCTAssertTrue(error is WebSocketTransportError)
    }

    func testDuplicateCloseAndCloseThenErrorExposeOnlyFirstClose() async {
        let (connection, _) = makeConnection()
        connection.handleSocketClosed(code: 1000, reason: "first")
        connection.handleSocketClosed(code: 1001, reason: "duplicate")
        connection.handleTaskCompleted(error: DriverTestError.scripted)

        let first = startReceive(on: connection)
        guard case .success(.closed(let code, let reason)) = await first.value else {
            return XCTFail("first close must be the sole terminal event")
        }
        XCTAssertEqual(code, 1000)
        XCTAssertEqual(reason, "first")
        XCTAssertFalse(connection.debugReceiveState.hasPendingTerminal, "duplicates must not accumulate")

        for _ in 0..<3 {
            let repeated = startReceive(on: connection)
            guard case .failure(let error) = await repeated.value else {
                return XCTFail("repeated receives after terminal consumption must fail")
            }
            XCTAssertTrue(error is WebSocketTransportError)
        }
    }

    func testTerminalErrorThenClosePreservesOriginalErrorExactlyOnce() async {
        let (connection, _) = makeConnection()
        connection.handleTaskCompleted(error: DriverTestError.scripted)
        connection.handleSocketClosed(code: 1000, reason: "late-close")

        let first = startReceive(on: connection)
        guard case .failure(let error) = await first.value else {
            return XCTFail("the first accepted terminal error must surface")
        }
        XCTAssertTrue(error is DriverTestError)
        XCTAssertFalse(connection.debugReceiveState.hasPendingTerminal)

        let second = startReceive(on: connection)
        guard case .failure(let ended) = await second.value else {
            return XCTFail("the late close must not add a terminal event")
        }
        XCTAssertTrue(ended is WebSocketTransportError)
    }

    // MARK: - Explicit close versus an already accepted terminal result

    func testQueuedDelegateCloseSurvivesExplicitClose() async {
        let (connection, driver) = makeConnection()
        connection.handleSocketClosed(code: 1000, reason: "queued")
        connection.close()

        XCTAssertEqual(driver.cancelCount, 1, "explicit close still cancels the driver exactly once")
        var state = connection.debugReceiveState
        XCTAssertTrue(state.ended)
        XCTAssertTrue(state.hasPendingTerminal, "explicit close must not erase the accepted delegate close")

        let first = startReceive(on: connection)
        guard case .success(.closed(let code, let reason)) = await first.value else {
            return XCTFail("the accepted first close must stay consumable across explicit close")
        }
        XCTAssertEqual(code, 1000)
        XCTAssertEqual(reason, "queued")

        let second = startReceive(on: connection)
        guard case .failure(let error) = await second.value else {
            return XCTFail("the terminal result is consumable exactly once")
        }
        XCTAssertTrue(error is WebSocketTransportError, "got \(error)")

        state = connection.debugReceiveState
        XCTAssertTrue(state.ended)
        XCTAssertFalse(state.hasPendingTerminal)
        XCTAssertFalse(state.hasPendingText)
        XCTAssertFalse(state.hasWaiter)
        XCTAssertEqual(driver.cancelCount, 1)
    }

    func testQueuedDriverErrorSurvivesExplicitClose() async {
        let (connection, driver) = makeConnection()
        connection.handleTaskCompleted(error: DriverTestError.scripted)
        connection.close()

        let first = startReceive(on: connection)
        guard case .failure(let error) = await first.value else {
            return XCTFail("the accepted terminal error must stay consumable across explicit close")
        }
        XCTAssertTrue(error is DriverTestError, "explicit close must not replace the original error, got \(error)")

        let second = startReceive(on: connection)
        guard case .failure(let ended) = await second.value else {
            return XCTFail("later receives fail as ended")
        }
        XCTAssertTrue(ended is WebSocketTransportError, "got \(ended)")
        XCTAssertEqual(driver.cancelCount, 1)
    }

    func testExplicitCloseAsFirstTerminalTransitionIsPermanentAndIdempotent() async {
        let (connection, driver) = makeConnection()
        connection.close()

        var state = connection.debugReceiveState
        XCTAssertTrue(state.ended, "explicit close as the first transition establishes ended state")
        XCTAssertFalse(state.hasPendingTerminal, "explicit close leaves no consumable terminal result")

        connection.handleSocketClosed(code: 1000, reason: "late")
        connection.handleTaskCompleted(error: DriverTestError.scripted)
        state = connection.debugReceiveState
        XCTAssertFalse(state.hasPendingTerminal, "late delegate terminals cannot replace explicit close")

        let receive = startReceive(on: connection)
        guard case .failure(let error) = await receive.value else {
            return XCTFail("receives after explicit close fail as ended")
        }
        XCTAssertTrue(error is WebSocketTransportError, "got \(error)")

        connection.close()
        connection.close()
        XCTAssertEqual(driver.cancelCount, 1, "repeated close stays idempotent")
    }

    func testCancelledReceiveDoesNotConsumeQueuedTerminal() async {
        let driver = ControlledSocketDriver()
        let gate = ReceiveInstallGate()
        let connection = URLSessionWebSocketTransportConnection(
            driver: driver,
            beforeReceiveWaiterInstall: { gate.wait() }
        )
        connection.handleSocketClosed(code: 1001, reason: "queued")

        let cancelled = startReceive(on: connection)
        let entered = await waitUntil { gate.hasEntered }
        XCTAssertTrue(entered, "receive must reach the deterministic pre-install gate")

        cancelled.cancel()
        gate.release()
        guard case .failure(let error) = await cancelled.value else {
            return XCTFail("a cancelled receive must throw, not deliver")
        }
        XCTAssertTrue(error is CancellationError, "got \(error)")
        XCTAssertTrue(
            connection.debugReceiveState.hasPendingTerminal,
            "a cancelled receive must not swallow the single consumable terminal result"
        )

        connection.close()
        XCTAssertTrue(
            connection.debugReceiveState.hasPendingTerminal,
            "explicit close after the cancelled receive must also preserve it"
        )

        let next = startReceive(on: connection)
        guard case .success(.closed(let code, let reason)) = await next.value else {
            return XCTFail("terminal ownership was lost")
        }
        XCTAssertEqual(code, 1001)
        XCTAssertEqual(reason, "queued")

        let later = startReceive(on: connection)
        guard case .failure(let ended) = await later.value else {
            return XCTFail("the consumed terminal cannot be consumed twice")
        }
        XCTAssertTrue(ended is WebSocketTransportError, "got \(ended)")
        XCTAssertEqual(driver.receiveCallCount, 0, "no driver receive may start on an ended connection")
        XCTAssertEqual(driver.cancelCount, 1)
    }

    func testTerminalTaskErrorSurfacesExactlyOnce() async throws {
        let (connection, _) = makeConnection()
        connection.handleTaskCompleted(error: DriverTestError.scripted)

        let first = startReceive(on: connection)
        guard case .failure(let error) = await first.value else {
            return XCTFail("the recorded terminal error must surface")
        }
        XCTAssertTrue(error is DriverTestError, "got \(error)")

        let second = startReceive(on: connection)
        guard case .failure(let secondError) = await second.value else {
            return XCTFail("subsequent receives throw ended")
        }
        XCTAssertTrue(secondError is WebSocketTransportError, "got \(secondError)")
    }

    // MARK: - Sends and pings through the driver

    func testSendAndPingDelegateToTheDriver() async throws {
        let (connection, driver) = makeConnection()
        try await connection.send(text: "hello")
        XCTAssertEqual(driver.sentTexts, ["hello"])

        // Success path: the driver's pong resolves the awaited ping.
        let ping = Task { try await connection.sendPing() }
        let pingArmed = await waitUntil { driver.pendingPingCount == 1 }
        XCTAssertTrue(pingArmed, "ping handler must be registered with the driver")
        driver.takePingCompletion()?(nil)
        try await ping.value

        // Failure path: a scripted pong error is thrown to the caller.
        let failingPing = Task { try await connection.sendPing() }
        let armed = await waitUntil { driver.pendingPingCount == 1 }
        XCTAssertTrue(armed)
        driver.takePingCompletion()?(DriverTestError.scripted)
        do {
            _ = try await failingPing.value
            XCTFail("ping must rethrow the driver error")
        } catch {
            XCTAssertTrue(error is DriverTestError, "got \(error)")
        }
    }
}
