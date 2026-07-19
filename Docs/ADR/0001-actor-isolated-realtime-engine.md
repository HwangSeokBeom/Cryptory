# ADR 0001 — Actor-isolated real-time market stream engine

- Status: Accepted
- Date: 2026-07-18
- Branch: `refactor/portfolio-realtime-foundation`

## Context

The public market WebSocket path (`Cryptory/Services/WebSocketService.swift`, `WebSocketService`) is a `final class` declared `@unchecked Sendable` with no compensating synchronization. Its mutable state — `webSocketTask`, `subscriptions`, `connectionState`, `intentionalDisconnect`, `reconnectWorkItem` — is read and written from at least three execution contexts:

1. `URLSessionWebSocketTask` receive/send completion handlers (background queue),
2. the `@MainActor` `CryptoViewModel` calling `connect`/`disconnect`/`updateSubscriptions`,
3. reconnect `DispatchWorkItem`s on the main queue.

Verified defects of the current design (file/line references as of this branch's base commit):

- **Data races by construction**: no lock, queue, or actor protects any field; `@unchecked Sendable` (`WebSocketService.swift:309`, `:555`) silences the compiler without adding safety.
- **No generation checks**: a successful receive unconditionally sets `connectionState = .connected` (`:426`), so a late callback from an old socket can resurrect a connection the consumer just closed; `intentionalDisconnect` is consulted only on the failure path (`:442`).
- **Reconnect policy**: fixed 2-second delay, no backoff, no jitter, no cap for the public socket (`:448-458`); failures can be reported concurrently from receive and send paths.
- **No heartbeat**: `sendPing` is never called; half-open sockets are undetected.
- **Unbounded main-thread pressure**: one `DispatchQueue.main.async` per message in the service (`:513-530`) plus one `Task { @MainActor }` per message in the view model (`CryptoViewModel.swift:9348-9466`).
- **No subscription ownership**: plain set replacement; no reference counting; no convergence guarantees under rapid replacement.

The app targets Swift 6 with approachable concurrency; the rest of the codebase is moving toward structured concurrency. ~180 existing view-model tests and active App Review work make a big-bang rewrite of consumers unacceptable.

## Decision

Replace the public market WebSocket path with an actor-isolated pipeline in `Cryptory/Services/Realtime/`:

1. **`MarketStreamEngine` is an `actor`** and the sole owner of connection state, socket generation, subscription registry, reconnect/heartbeat state, event buffers, and metrics. Compiler-enforced isolation replaces `@unchecked Sendable`.
2. **Transport behind a protocol** (`WebSocketTransport`): the engine never touches `URLSessionWebSocketTask`; production uses `URLSessionWebSocketTransport`, tests use a scripted transport. The transport cannot mutate UI or engine state; the engine pulls events one at a time via `receive()`, so at most one raw frame is held app-side before decoding (see REALTIME_PIPELINE.md, "Transport ingress").
3. **Monotonic connection generation**: every attempt gets a new generation; all transport events and timer callbacks are generation-tagged and stale ones are ignored for state, events, reconnect, subscriptions, and heartbeat.
4. **Events via `AsyncStream<MarketStreamEvent>`** with engine-owned bounded buffering and per-kind coalescing policies (tickers latest-per-market; orderbook snapshot replacement; bounded trade batches; candle merge by interval+timestamp) — documented in [REALTIME_PIPELINE.md](../REALTIME_PIPELINE.md).
5. **Deterministic policies as values**: `ReconnectPolicy` (exponential backoff, bounded jitter, cap, documented reset condition) and `HeartbeatPolicy` (ping interval, pong timeout) are plain structs; the engine takes an injected clock abstraction so tests never sleep on the wall clock.
6. **Compatibility adapter, not call-site rewrite**: `MarketStreamUIAdapter` implements the existing `PublicWebSocketServicing` protocol on `MainActor` (the protocol's callback closures are declared `@MainActor`, letting the view model apply state synchronously). `CryptoViewModel`'s binding code is unchanged; only the default service instance switches to the adapter. The legacy public `WebSocketService` is deprecated but kept compiling.
7. **Private socket excluded**: `PrivateWebSocketService` is not migrated in this change (its auth-token lifecycle deserves its own design pass); it remains on the legacy implementation and is a documented follow-up.

## Alternatives considered

| Alternative | Why rejected |
| --- | --- |
| Add a lock/serial queue inside the existing classes | Patches the races but keeps timer/callback spaghetti, keeps `@unchecked Sendable`, adds no generation safety, and is hard to test deterministically |
| Combine publishers + `receive(on:)` | The codebase's direction is structured concurrency; Combine adds a second async model and still needs manual state synchronization |
| Third-party WebSocket library (e.g. Starscream) | The defects are in state ownership, not the socket API; a dependency adds supply-chain surface without fixing isolation |
| Full rewrite including all consumers | Violates the incremental-migration constraint; ~20k-line view model and live App Review make regression risk unacceptable |
| GCD-based "socket manager" singleton | Singletons hurt testability; actors give the same serialization with compiler enforcement and async integration |

## Consequences

Positive:

- Data races in the public path become compile-time impossible (actor isolation, `Sendable` events; the single `@unchecked Sendable` remaining in the new path is the documented, mutex-guarded URLSession transport boundary).
- Every scenario — reconnect storms, stale callbacks, heartbeat timeouts, 100k-event replays — is deterministically testable via scripted transport + manual clock.
- Main-thread pressure drops from two hops per message to one adapter delivery per coalesced batch.
- Metrics and diagnostics (Pipeline Lab) come for free from single ownership.

Negative / accepted costs:

- Two public-socket implementations coexist until the legacy one is deleted (deprecation path documented).
- The closure-based `PublicWebSocketServicing` surface survives one more phase; direct `AsyncStream` consumption in the view model is deferred.
- Actor hops add a scheduling boundary per message batch; measured (not assumed) impact is tracked in [PERFORMANCE_BASELINE.md](../PERFORMANCE_BASELINE.md).
- The private socket keeps the legacy risks until its follow-up migration.

## Follow-ups

1. Migrate `PrivateWebSocketService` onto the engine/transport design (token-bearing connect, order/fill channels).
2. Move `CryptoViewModel` from adapter callbacks to direct `AsyncStream` consumption, then delete the legacy service and protocol.
3. MetricKit/Crashlytics field diagnostics (not present today; see INCIDENT_PLAYBOOK.md gaps).
