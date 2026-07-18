import Foundation

/// Minimal clock abstraction so the engine's timers (reconnect backoff,
/// heartbeat) are deterministic in tests. Production uses `ContinuousClock`;
/// tests use `ManualTestClock`, which only advances when told to.
protocol RealtimeClock: Sendable {
    /// Monotonic elapsed time since an arbitrary fixed origin.
    var now: Duration { get }

    /// Suspends for `duration`, honoring task cancellation.
    func sleep(for duration: Duration) async throws
}

struct ContinuousRealtimeClock: RealtimeClock {
    private let origin = ContinuousClock.now

    var now: Duration {
        origin.duration(to: ContinuousClock.now)
    }

    func sleep(for duration: Duration) async throws {
        try await ContinuousClock().sleep(for: duration)
    }
}
