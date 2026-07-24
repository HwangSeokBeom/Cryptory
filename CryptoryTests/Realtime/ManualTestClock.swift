import Foundation
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

    private let state = TestLock(State())

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
                enum Disposition {
                    case park
                    case resumeNow
                    case throwCancelled
                }
                let disposition: Disposition = state.withLock { state in
                    // Cancel-before-park: when the owning task was cancelled
                    // before this continuation body ran, the onCancel handler
                    // has already fired and found nothing to remove. Parking
                    // here would create a sleeper nothing can ever resume —
                    // and its presence would satisfy sleeper-count waits for
                    // a timer that is not actually armed.
                    if Task.isCancelled { return .throwCancelled }
                    guard duration > .zero else { return .resumeNow }
                    state.sleepers.append(
                        Sleeper(id: id, deadline: state.now + duration, continuation: continuation)
                    )
                    return .park
                }
                switch disposition {
                case .park:
                    break
                case .resumeNow:
                    continuation.resume()
                case .throwCancelled:
                    continuation.resume(throwing: CancellationError())
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
    /// clock. The condition is the synchronization; the wall-clock deadline is
    /// only a deadlock guard so a failure surfaces as `false` instead of a
    /// hang. (A yield-count bound proved scheduler-dependent and flaky under
    /// full-suite load.)
    @discardableResult
    func waitForSleepers(atLeast count: Int, timeout: Duration = .seconds(30)) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while sleeperCount < count {
            if ContinuousClock.now >= deadline { return false }
            await Task.yield()
        }
        return true
    }
}
