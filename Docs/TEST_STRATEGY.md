# Test Strategy

This document records what the test suite actually covers today, the injection-based design that makes it possible, the gaps in current coverage, and the deterministic realtime test layer added on this branch. Planned work is explicitly labeled as planned.

Volatile inventory numbers (per-file line counts, per-class test tallies, source line references) are deliberately **not** recorded here — they drift with every commit and stale copies are worse than none. To regenerate current numbers: run the suite (`scripts/ci_test.sh test`, or `test CryptoryTests/<Class>` for one class) and read the `Executed N tests` summary, or `grep -c "func test" CryptoryTests/<File>.swift` for a static tally. The authoritative full-suite count is the `Executed N tests` line of the latest hosted CI run referenced in PR #1.

Last updated: 2026-07-19 (branch refactor/portfolio-realtime-foundation)

## 1. Current state: CryptoryTests (unit)

| Suite | Coverage |
| --- | --- |
| `NetworkAndAuthTests` | API configuration resolution (`AppRuntimeConfiguration`), auth service contracts, response parsing |
| `ViewModelStateTests` | `CryptoViewModel` state transitions across tabs, auth, market, portfolio, chart, and kimchi flows |
| `FormAndViewStateTests` | Form and view-state logic |
| `PublicContentRepositoryTests` | Public content (news/analysis) repository behavior |
| `WebSocketParserTests` | Parser contracts for `MarketWebSocketMessageParser` (envelope → ticker/orderbook/trades/candles, control-frame dropping); also the CI smoke class |
| `ChartSettingsTests` | Chart settings behavior |
| `MarketPresentationPublicationTests` | The presentation-publication contract (staged build gate) |
| `TestIsolationRegressionTests` | Cross-test state-isolation boundaries |
| `KimchiSnapshotGateTests` | Cancellation safety of the test-only kimchi snapshot gate (waiter removal, single resume, open/cancel interleaving) |

Test doubles in `TestDoubles.swift` follow the Stub/Spy/Recording/Manual taxonomy, including WebSocket doubles and a URL-level spy:

- `NoOpPublicWebSocketService`, `RecordingPublicWebSocketService`
- `ManualPublicWebSocketService`: `emitState` / `emitTicker` / `emitTrades` / `emitCandles` (no `emitOrderbook` today)
- `NoOpPrivateWebSocketService`
- `URLProtocolSpy`: intercepts URLSession traffic so no test touches the network
- `KimchiSnapshotGate` + `DelayedKimchiPremiumRepository`: cancellation-safe latching gate so snapshot arrival is a test-controlled event, never a wall-clock race

## 2. Current state: CryptoryUITests

`CryptoryUITests/CryptoryUITests.swift` contains 3 fixture-driven tests plus `CryptoryUITestsLaunchTests`. Fixtures come from `Cryptory/UITestFixtureFactory.swift` with `UITestPublic/PrivateWebSocketService` standing in for live sockets, so UI tests run against deterministic data.

## 3. Testing philosophy

- Protocol-based constructor injection. `CryptoViewModel` takes optional protocol parameters defaulting to `nil` and resolves `Live*` implementations in `init` (`Cryptory/ViewModels/CryptoViewModel.swift:1449–1465`). Tests pass doubles for any subset (repositories, auth service, WS services, session store).
- No live network in tests. All network is served by stubs or `URLProtocolSpy`; all realtime data by manual WS doubles.
- Contract tests at seams. Parser tests pin the gateway envelope contract (`Cryptory/Services/WebSocketService.swift:124–246`) independent of transport.
- Per-test state isolation. Any test asserting symbol-image state injects a fresh `AssetImageClient(namespace: UUID().uuidString)` instead of the `.shared` singleton, whose URL-keyed failure cooldowns otherwise leak across tests that reuse fixture image URLs (`TestIsolationRegressionTests` pins the instance boundary). Image fixtures that will actually be fetched use local temp PNG files, never remote URLs: a dead remote host makes the assertion race the OS negative-DNS cache, which earlier tests warm (fast terminal failure) or leave cold (slow failure), flipping outcomes by suite order. Tests exercising live candle merges anchor trade timestamps to the candle bucket the view model actually created, never to a test-captured `Date()` that can race a minute boundary. Bounded waits are wall-clock deadlines around exact conditions — the condition is the synchronization; the deadline only guards against hangs.

## 4. Current gaps (honest)

- The **legacy** `WebSocketService` (deprecated) still owns a real `URLSessionWebSocketTask` with no injectable transport or clock, so its timing behavior (fixed 2s public reconnect, private exponential backoff) remains untested as written. The **new** realtime path is fully covered: engine behavior via `ScriptedWebSocketTransport` + `ManualTestClock`, and the production `URLSessionWebSocketTransportConnection` state machine directly via the internal `WebSocketSocketDriver` seam (`URLSessionTransportStateMachineTests`).
- Private WS delivery has no double beyond `NoOpPrivateWebSocketService` — private message flows into the ViewModel are not exercised.
- `ManualPublicWebSocketService` lacks `emitOrderbook`, so orderbook delivery into the ViewModel is untested.
- Live production WSS endpoints are never exercised by any automated test; Foundation/network-stack internal buffering is opaque and outside the proven repository-owned memory bound.
- (Resolved on this branch) Test targets previously built with `SWIFT_VERSION` 5.0 while the app target was 6.0; both test targets now build with Swift 6.0.

## 5. Deterministic realtime test layer (added on this branch)

This branch introduces an actor-isolated market stream engine (`Cryptory/Services/Realtime/`) behind the existing `PublicWebSocketServicing` protocol, designed for determinism-first testing. The accompanying test layer lives under `CryptoryTests/Realtime/` (`MarketStreamEngineTests`, `RealtimeComponentTests`, `RealtimeTransportTests`, `RealtimeLifecycleTests`, `RealtimeMetricsSemanticsTests`, `RealtimeReplayBenchmarkTests`, `MarketIdentityTests` — complete exchange/quote/symbol identity, single-live-identity enforcement, stale-identity token validation — and `URLSessionTransportStateMachineTests` — the production transport wrapper's state machine driven through the internal `WebSocketSocketDriver` seam; plus `ScriptedWebSocketTransport`, `ManualTestClock`, `RealtimeFixtureLoader`; the presentation-publication contract is covered by `CryptoryTests/MarketPresentationPublicationTests`). The suite is the source of truth for its own count — run `scripts/ci_test.sh test CryptoryTests/MarketStreamEngineTests` (or the full unit suite) rather than trusting a number written here; every test passes in the environment recorded in `Docs/PERFORMANCE_BASELINE.md`.

Planned components:

- `ScriptedWebSocketTransport` — an injected transport whose events (connect results, messages, failures, closes) are scripted per test, replacing `URLSessionWebSocketTask`.
- `ManualTestClock` — an injected clock; tests advance time explicitly, so no arbitrary `sleep` is used for correctness (reconnect delays, heartbeat timeouts, and backoff are asserted against advanced time, not wall time).
- `RealtimeFixtureLoader` — replays JSON fixtures through the scripted transport. Fixture classes: normal stream, duplicate messages, out-of-order messages, malformed messages, reconnect sequences, and high-volume streams. Fixtures are privacy-safe (synthetic symbols/values, no real account data).

Planned coverage: 30 deterministic scenarios across these categories:

| Category | What it pins down |
| --- | --- |
| Duplicate connect | Second `connect()` while connected/connecting is a no-op |
| Idempotent disconnect | Repeated `disconnect()` is safe |
| Generation handling | Events from a superseded connection generation are ignored |
| Subscription refcounting | Add/remove of overlapping subscriptions sends the minimal diff |
| Reconnect replay | Full subscription set replayed after reconnect |
| Stale-callback suppression | Callbacks from torn-down sessions never fire |
| Heartbeat timeout | Missed heartbeats force a reconnect (the legacy service has none) |
| Backoff/jitter bounds | Delays stay within configured min/max envelope |
| Lifecycle policy | Scene-phase transitions produce the intended connect/disconnect behavior |
| Coalescing | Burst updates coalesce into bounded main-thread emissions |
| Bounded buffers | Backpressure drops/limits instead of unbounded queueing |
| Backoff preservation | Subscription churn during `waitingToReconnect` never cancels/resets the timer; explicit `connect()` is the documented bypass |
| Sender ownership | A stale sender resuming after teardown cannot clear the new sender, drain a newer outbox, or fail a newer generation |
| Idle-close convergence | A → [] → B during a suspended send keeps the socket and converges to the final set |
| Consumer cancellation | Cancelling a consumer task releases the consumer, its buffer (counted drops), registry ownership, and closes the socket for the final owner |
| Adapter lifecycle | Explicit `shutdown()` and last-reference deallocation both release engine ownership; no callbacks after shutdown |
| Transport ingress bound | At most one `receive()` outstanding; producer bursts never build an app-side raw-frame queue (incl. 100k replay) |
| Metrics semantics | Global ingress vs per-consumer delivery counters stay separate; documented conservation equations hold |
| Presentation publication | `refreshMarketData()` returns only after rows publish; a superseded row builder cannot overwrite newer rows |
| Malformed-message resilience | Bad payloads are dropped without tearing down the stream |
| 100k-event replay | High-volume fixture replays to completion with stable counts (also feeds `Docs/PERFORMANCE_BASELINE.md`) |

## 6. Running tests locally

Unit tests run through the **`Cryptory-UnitTests` scheme** via `scripts/ci_test.sh` — never through the shared `Cryptory-Dev` scheme, whose test action includes `CryptoryUITests` (and `-skip-testing` does **not** stop the UI-test runner from being *built*). The script is the supported entry point locally and in CI:

```sh
# Full local flow: build-for-testing, explicit simulator boot, smoke,
# then the complete CryptoryTests suite (all test-without-building).
scripts/ci_test.sh

# Individual phases / focused suites:
scripts/ci_test.sh build
scripts/ci_test.sh boot
scripts/ci_test.sh smoke
scripts/ci_test.sh test                                   # full CryptoryTests
scripts/ci_test.sh test CryptoryTests/MarketStreamEngineTests
```

Every phase is bounded by an in-script watchdog that collects simulator/process diagnostics before failing, so a hang is diagnosed instead of eating the job timeout. Simulator selection is dynamic (`scripts/ci_destination.sh`) and cached per DerivedData path so all phases use the same device; no signing is needed anywhere (`CODE_SIGNING_ALLOWED=NO`).

UI tests are separate: run them locally through the UI-capable `Cryptory-Dev` scheme (`xcodebuild test … -only-testing:CryptoryUITests`); they are not part of the unit pipeline.

Verified environment: Xcode 26.6, iOS 26.3–26.5 simulator runtimes.

## 7. Hosted CI (`.github/workflows/ios.yml`)

The workflow runs on pushes/PRs to `main`/`dev` and executes, in order:

1. shell regression tests for the CI helpers (`scripts/test_ci_destination.sh`, `test_ci_test_lib.sh`, `test_ci_whitespace_check.sh`, `test_verify_no_secrets.sh`);
2. whitespace check (`scripts/ci_whitespace_check.sh`) and secret scan (`scripts/verify_no_secrets.sh`);
3. unsigned app build (`scripts/ci_build.sh Cryptory-Dev`);
4. `scripts/ci_test.sh build` — `Cryptory-UnitTests` build-for-testing on a separate DerivedData path, then proves the UI-test runner was **not** built;
5. `scripts/ci_test.sh boot` — explicit simulator boot via `simctl bootstatus` (never xcodebuild's implicit boot);
6. `scripts/ci_test.sh smoke` — deterministic smoke class (`CryptoryTests/WebSocketParserTests`) via test-without-building, isolating infrastructure failures from suite failures;
7. `scripts/ci_test.sh test` — the complete `CryptoryTests` suite (test-without-building);
8. `scripts/ci_test.sh test CryptoryTests/MarketStreamEngineTests` — focused realtime signal;
9. on failure or cancellation (including watchdog timeouts), xcresult bundles, logs, and collected diagnostics upload as artifacts.

UI tests are not run in hosted CI (shared-runner UI-test infrastructure is flaky); see section 6 for the local UI-test path.
