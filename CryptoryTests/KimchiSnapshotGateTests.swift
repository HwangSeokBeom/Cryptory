import XCTest
@testable import Cryptory

/// Single-purpose entry gate: parks exactly one task without being
/// cancellation-aware, so a test can cancel that task *before* it enters the
/// code under test. Event-driven (an observer continuation, not polling).
private actor WaitEntryGate {
    private var parked: CheckedContinuation<Void, Never>?
    private var parkObserver: CheckedContinuation<Void, Never>?

    func park() async {
        await withCheckedContinuation { continuation in
            parked = continuation
            parkObserver?.resume()
            parkObserver = nil
        }
    }

    func awaitParked() async {
        if parked != nil { return }
        await withCheckedContinuation { parkObserver = $0 }
    }

    func release() {
        parked?.resume()
        parked = nil
    }
}

/// Deterministic cancellation-safety tests for `KimchiSnapshotGate`. All
/// synchronization is event-driven (`waitUntilWaiterCount`, entry-gate
/// observers); there is no sleeping, no wall-clock timing, and no polling.
/// `CheckedContinuation` diagnostics double as the double-resume detector.
final class KimchiSnapshotGateTests: XCTestCase {
    func testCancellationBeforeOpenRemovesWaiterAndThrows() async {
        let gate = KimchiSnapshotGate()
        let waiter = Task { () -> Result<Void, Error> in
            do {
                try await gate.wait()
                return .success(())
            } catch {
                return .failure(error)
            }
        }
        await gate.waitUntilWaiterCount(1)

        waiter.cancel()
        guard case .failure(let error) = await waiter.value else {
            return XCTFail("a waiter cancelled while parked must throw")
        }
        XCTAssertTrue(error is CancellationError, "got \(error)")
        let count = await gate.waiterCount
        XCTAssertEqual(count, 0, "cancellation must remove the parked waiter")
    }

    func testOpenAfterCancellationDoesNotResumeTheCancelledWaiterAgain() async {
        let gate = KimchiSnapshotGate()
        let waiter = Task { () -> Result<Void, Error> in
            do {
                try await gate.wait()
                return .success(())
            } catch {
                return .failure(error)
            }
        }
        await gate.waitUntilWaiterCount(1)
        waiter.cancel()
        guard case .failure = await waiter.value else {
            return XCTFail("the cancelled waiter must have thrown before open")
        }

        // A second resume of the same checked continuation would be reported
        // by the runtime; reaching the assertions below proves open() only
        // latched the gate.
        await gate.open()
        let count = await gate.waiterCount
        XCTAssertEqual(count, 0)

        do {
            try await gate.wait()
        } catch {
            XCTFail("after open, a fresh wait must pass straight through, got \(error)")
        }
    }

    func testOpenResumesOnlyLiveWaiters() async {
        let gate = KimchiSnapshotGate()
        func spawnWaiter() -> Task<Result<Void, Error>, Never> {
            Task {
                do {
                    try await gate.wait()
                    return .success(())
                } catch {
                    return .failure(error)
                }
            }
        }
        let first = spawnWaiter()
        await gate.waitUntilWaiterCount(1)
        let second = spawnWaiter()
        await gate.waitUntilWaiterCount(2)
        let third = spawnWaiter()
        await gate.waitUntilWaiterCount(3)

        second.cancel()
        await gate.waitUntilWaiterCount(2)

        await gate.open()
        guard case .success = await first.value else {
            return XCTFail("live waiter one must be resumed by open")
        }
        guard case .failure(let cancelled) = await second.value else {
            return XCTFail("the cancelled waiter must not be resurrected by open")
        }
        XCTAssertTrue(cancelled is CancellationError, "got \(cancelled)")
        guard case .success = await third.value else {
            return XCTFail("live waiter three must be resumed by open")
        }
        let count = await gate.waiterCount
        XCTAssertEqual(count, 0, "open must leave no registered waiter behind")
    }

    func testCancellationBeforeWaitEntryNeverRegistersAWaiter() async {
        let gate = KimchiSnapshotGate()
        let entry = WaitEntryGate()
        let waiter = Task { () -> Result<Void, Error> in
            await entry.park()
            do {
                try await gate.wait()
                return .success(())
            } catch {
                return .failure(error)
            }
        }
        await entry.awaitParked()

        waiter.cancel()
        await entry.release()
        guard case .failure(let error) = await waiter.value else {
            return XCTFail("a task cancelled before wait() must throw at entry")
        }
        XCTAssertTrue(error is CancellationError, "got \(error)")
        let count = await gate.waiterCount
        XCTAssertEqual(count, 0, "an already-cancelled task must never park")
    }

    func testOpenThenLateCancellationLeaksNothing() async {
        let gate = KimchiSnapshotGate()
        let waiter = Task { () -> Result<Void, Error> in
            do {
                try await gate.wait()
                return .success(())
            } catch {
                return .failure(error)
            }
        }
        await gate.waitUntilWaiterCount(1)

        await gate.open()
        guard case .success = await waiter.value else {
            return XCTFail("open must resume the parked waiter normally")
        }
        // Cancellation arriving after the waiter completed must be inert; a
        // double resume would be reported by the checked continuation.
        waiter.cancel()
        let count = await gate.waiterCount
        XCTAssertEqual(count, 0)
    }

    func testCancellationPropagatesThroughDelayedRepository() async {
        let gate = KimchiSnapshotGate()
        let repository = DelayedKimchiPremiumRepository(
            snapshotsByExchange: [:],
            gatesByExchange: [.upbit: gate]
        )
        let fetch = Task { () -> Result<KimchiPremiumSnapshot, Error> in
            do {
                let snapshot = try await repository.fetchSnapshot(exchange: .upbit, symbols: ["BTC"])
                return .success(snapshot)
            } catch {
                return .failure(error)
            }
        }
        await gate.waitUntilWaiterCount(1)

        fetch.cancel()
        guard case .failure(let error) = await fetch.value else {
            return XCTFail("a cancelled gated fetch must throw, not return a snapshot")
        }
        XCTAssertTrue(error is CancellationError, "got \(error)")
        let count = await gate.waiterCount
        XCTAssertEqual(count, 0)
    }
}
