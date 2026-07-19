# Test Strategy

This document records what the test suite actually covers today, the injection-based design that makes it possible, the gaps in current coverage, and the deterministic realtime test layer added on this branch. Counts and file references below were verified against the repository; planned work is explicitly labeled as planned.

Last updated: 2026-07-18 (branch refactor/portfolio-realtime-foundation)

## 1. Current state: CryptoryTests (unit)

| File | Size / count | Coverage |
| --- | --- | --- |
| `CryptoryTests/NetworkAndAuthTests.swift` | 1,274 lines, 30 tests | API configuration resolution (`AppRuntimeConfiguration`), auth service contracts, response parsing |
| `CryptoryTests/ViewModelStateTests.swift` | 7,181 lines, ~180 async tests | `CryptoViewModel` state transitions across tabs, auth, market, portfolio flows |
| `CryptoryTests/FormAndViewStateTests.swift` | — | Form and view-state logic |
| `CryptoryTests/PublicContentRepositoryTests.swift` | — | Public content (news/analysis) repository behavior |
| `CryptoryTests/WebSocketParserTests.swift` | 176 lines | Parser contracts for `MarketWebSocketMessageParser` (envelope → ticker/orderbook/trades/candles, control-frame dropping) |
| `CryptoryTests/ChartSettingsTests.swift` | — | Chart settings behavior |
| `CryptoryTests/TestDoubles.swift` | 1,251 lines | Shared test doubles (below) |

Test doubles in `TestDoubles.swift` follow the Stub/Spy/Recording/Manual taxonomy, including WebSocket doubles and a URL-level spy:

- `NoOpPublicWebSocketService` (line 1099), `RecordingPublicWebSocketService` (1116)
- `ManualPublicWebSocketService` (1148): `emitState` / `emitTicker` / `emitTrades` / `emitCandles` (no `emitOrderbook` today)
- `NoOpPrivateWebSocketService` (1176)
- `URLProtocolSpy` (1191): intercepts URLSession traffic so no test touches the network

## 2. Current state: CryptoryUITests

`CryptoryUITests/CryptoryUITests.swift` contains 3 fixture-driven tests plus `CryptoryUITestsLaunchTests`. Fixtures come from `Cryptory/UITestFixtureFactory.swift` with `UITestPublic/PrivateWebSocketService` standing in for live sockets, so UI tests run against deterministic data.

## 3. Testing philosophy

- Protocol-based constructor injection. `CryptoViewModel` takes optional protocol parameters defaulting to `nil` and resolves `Live*` implementations in `init` (`Cryptory/ViewModels/CryptoViewModel.swift:1449–1465`). Tests pass doubles for any subset (repositories, auth service, WS services, session store).
- No live network in tests. All network is served by stubs or `URLProtocolSpy`; all realtime data by manual WS doubles.
- Contract tests at seams. Parser tests pin the gateway envelope contract (`Cryptory/Services/WebSocketService.swift:124–246`) independent of transport.
- Per-test state isolation. Any test asserting symbol-image state injects a fresh `AssetImageClient(namespace: UUID().uuidString)` instead of the `.shared` singleton, whose URL-keyed failure cooldowns otherwise leak across tests that reuse fixture image URLs (`TestIsolationRegressionTests` pins the instance boundary). Image fixtures that will actually be fetched use local temp PNG files, never remote URLs: a dead remote host makes the assertion race the OS negative-DNS cache, which earlier tests warm (fast terminal failure) or leave cold (slow failure), flipping outcomes by suite order. Tests exercising live candle merges anchor trade timestamps to the candle bucket the view model actually created, never to a test-captured `Date()` that can race a minute boundary. Bounded waits are wall-clock deadlines around exact conditions — the condition is the synchronization; the deadline only guards against hangs.

## 4. Current gaps (honest)

- No tests for reconnect, backoff, heartbeat, race conditions, or the transport layer itself. `WebSocketService` owns a real `URLSessionWebSocketTask` with no injectable transport or clock, so its timing behavior (fixed 2s public reconnect, private exponential backoff) is untested and untestable as written.
- Private WS delivery has no double beyond `NoOpPrivateWebSocketService` — private message flows into the ViewModel are not exercised.
- `ManualPublicWebSocketService` lacks `emitOrderbook`, so orderbook delivery into the ViewModel is untested.
- (Resolved on this branch) Test targets previously built with `SWIFT_VERSION` 5.0 while the app target was 6.0; both test targets now build with Swift 6.0.

## 5. Deterministic realtime test layer (added on this branch)

This branch introduces an actor-isolated market stream engine (`Cryptory/Services/Realtime/`) behind the existing `PublicWebSocketServicing` protocol, designed for determinism-first testing. The accompanying test layer lives under `CryptoryTests/Realtime/` (`MarketStreamEngineTests`, `RealtimeComponentTests`, `RealtimeTransportTests`, `RealtimeLifecycleTests`, `RealtimeMetricsSemanticsTests`, `RealtimeReplayBenchmarkTests`, plus `ScriptedWebSocketTransport`, `ManualTestClock`, `RealtimeFixtureLoader`; the presentation-publication contract is covered by `CryptoryTests/MarketPresentationPublicationTests`). The suite is the source of truth for its own count — run `scripts/ci_test.sh CryptoryTests/MarketStreamEngineTests` (or the full unit suite) rather than trusting a number written here; every test passes in the environment recorded in `Docs/PERFORMANCE_BASELINE.md`.

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

Use the shared `Cryptory-Dev` scheme with a dynamically chosen simulator (no signing needed):

```sh
xcodebuild test \
  -project Cryptory.xcodeproj \
  -scheme Cryptory-Dev \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO
```

Pick any installed simulator (`xcrun simctl list devices available`) — the suite has no device dependency. Verified environment: Xcode 26.6, iOS 26.3–26.5 simulator runtimes.

## 7. CI hook (added on this branch)

`scripts/ci_test.sh` and `.github/workflows/ios.yml` are added on this branch (they do not exist on `main` as of this writing). The script wraps the `xcodebuild test` invocation above with dynamic simulator selection and `CODE_SIGNING_ALLOWED=NO`; the workflow runs it on pushes/PRs. Until this branch lands on `main`, CI does not run automatically; tests are run locally via the command in section 6.
