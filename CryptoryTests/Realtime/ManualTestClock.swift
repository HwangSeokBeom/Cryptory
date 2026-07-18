import Foundation
import Synchronization
@testable import Cryptory

/// Deterministic clock for realtime tests: time only moves when `advance(by:)`
/// is called, and sleepers resume in deadline order. No wall-clock waits.
final class ManualTestClock: RealtimeClock {
    private struct Sleeper {
        let id: UUID
        let deadline: Duration
        let continuation: CheckedContinuation<Void, Error>
    }

    private struct State {
        var now: Duration = .zero
        var sleepers: [Sleeper] = []
    }

    private let state = Mutex(State())

    var now: Duration {
        state.withLock { $0.now }
    }

    var sleeperCount: Int {
        state.withLock { $0.sleepers.count }
    }

    func sleep(for duration: Duration) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let resumeImmediately: Bool = state.withLock { state in
                    guard duration > .zero else { return true }
                    state.sleepers.append(
                        Sleeper(id: id, deadline: state.now + duration, continuation: continuation)
                    )
                    return false
                }
                if resumeImmediately {
                    continuation.resume()
                }
            }
        } onCancel: {
            let continuation: CheckedContinuation<Void, Error>? = state.withLock { state in
                guard let index = state.sleepers.firstIndex(where: { $0.id == id }) else { return nil }
                let sleeper = state.sleepers.remove(at: index)
                return sleeper.continuation
            }
            continuation?.resume(throwing: CancellationError())
        }
    }

    /// Advances time, resuming every sleeper whose deadline has passed, in
    /// deadline order.
    func advance(by duration: Duration) {
        let due: [CheckedContinuation<Void, Error>] = state.withLock { state in
            state.now = state.now + duration
            let now = state.now
            let dueSleepers = state.sleepers
                .filter { $0.deadline <= now }
                .sorted { $0.deadline < $1.deadline }
            state.sleepers.removeAll { $0.deadline <= now }
            return dueSleepers.map(\.continuation)
        }
        for continuation in due {
            continuation.resume()
        }
    }

    /// Cooperatively waits until at least `count` tasks are suspended on this
    /// clock. Bounded: fails the test path by returning `false` after
    /// `maxYields` scheduler yields instead of hanging.
    @discardableResult
    func waitForSleepers(atLeast count: Int, maxYields: Int = 100_000) async -> Bool {
        var yields = 0
        while sleeperCount < count {
            if yields >= maxYields { return false }
            yields += 1
            await Task.yield()
        }
        return true
    }
}
