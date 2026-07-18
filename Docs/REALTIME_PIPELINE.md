# Real-Time Pipeline

This document specifies the actor-isolated public market stream pipeline introduced on this branch (`Cryptory/Services/Realtime/`): its state machine, ownership rules, buffering/coalescing policies, reconnect and heartbeat behavior, and metrics. The private trading socket is *not* covered — it still uses the legacy implementation (documented follow-up).

Last updated: 2026-07-18 (branch `refactor/portfolio-realtime-foundation`)

## Components

| Component | Kind | Responsibility |
| --- | --- | --- |
| `MarketStreamEngine` | `actor` | Sole owner of connection state, socket generation, subscription registry, reconnect/heartbeat state, event buffering, metrics |
| `WebSocketTransport` | protocol | Abstract socket: open a connection, send text, send ping, receive an event stream, close. No URLSession types leak past it |
| `URLSessionWebSocketTransport` | struct/class | Production transport over `URLSessionWebSocketTask` |
| `MarketSubscriptionRegistry` | struct (engine-owned) | Reference-counted ownership of upstream subscriptions |
| `ReconnectPolicy` | struct | Exponential backoff parameters + delay computation |
| `HeartbeatPolicy` | struct | Ping cadence and timeout parameters |
| `MarketStreamDecoder` | enum/struct | Wire JSON → typed payloads (wraps the existing `MarketWebSocketMessageParser` contract) |
| `RealtimeMetrics` / `RealtimeMetricsSnapshot` | engine-owned / `Sendable` struct | Bounded in-memory counters and latency samples |
| `MarketStreamUIAdapter` | `@MainActor` class | Consumes the engine's `AsyncStream`, implements the legacy `PublicWebSocketServicing` protocol verbatim for `CryptoViewModel` |

## Ownership and isolation rules

- Only the `MarketStreamEngine` actor mutates: connection state, active socket generation, reconnect attempt count, subscriptions, heartbeat state, buffering state, metrics counters.
- The transport never mutates UI state and never calls back into the engine except by delivering transport events into the engine's receive loop.
- Events leave the engine exclusively through `AsyncStream<MarketStreamEvent>`.
- The adapter is the only component that touches `MainActor`; SwiftUI types never appear in the engine or transport.
- The new path contains no `@unchecked Sendable`. If a compatibility boundary ever requires one, it must be documented at the declaration.

## Connection state machine

```
idle ──connect()──▶ connecting ──first transport open──▶ connected
  ▲                     │  ▲                                │
  │                     │  └───backoff delay elapsed────┐   │ failure/heartbeat timeout
  └──disconnect()───────┴──────────────◀── waitingToReconnect ◀┘
```

- `connect()` / `disconnect()` / subscription replacement / lifecycle transitions are **idempotent**: repeated calls in the same state are no-ops.
- Exactly **one** live transport connection may exist at a time; the engine opens a new connection only after the previous generation is closed and discarded.
- With **zero subscriptions** the engine does not open (and tears down) the socket — preserving the legacy behavior where an empty subscription set disconnects.

## Connection generation

Every connection attempt increments a monotonically increasing `generation: UInt64`. Every transport event and every internal timer callback (reconnect, heartbeat) carries the generation it was created for. The engine ignores any callback whose generation is not current — a stale generation must never:

- update connection state,
- emit market events,
- schedule a reconnect,
- replace subscriptions,
- affect heartbeat state.

## Subscription ownership (reference counting)

`MarketSubscriptionRegistry` maps each `PublicMarketSubscription` to the set of consumer IDs that own it:

- Two consumers acquiring the same subscription → **one** upstream `subscribe` message.
- Releasing one of two owners → **no** upstream `unsubscribe`.
- Releasing the final owner → exactly **one** upstream `unsubscribe`.
- On reconnect, the active subscription set is replayed **exactly once** per new generation.
- Rapid replacement (`replace(owner:with:)` called in a burst) converges to the final intended set; intermediate states may skip wire messages entirely if they cancel out.

The UI adapter registers as one consumer and mirrors the legacy `updateSubscriptions(Set)` semantics; the DEBUG Realtime Pipeline Lab may register as an additional consumer without disturbing the adapter's subscriptions.

## Reconnect policy

`ReconnectPolicy` implements exponential backoff:

| Parameter | Default | Notes |
| --- | --- | --- |
| Initial delay | 1 s | configurable |
| Multiplier | 2.0 | 1, 2, 4, 8, … |
| Maximum delay | 30 s | cap |
| Jitter | ±20 % of the computed delay | bounded, uniformly distributed |
| Retry limit | unlimited while ≥1 subscription is active | documented choice: a market app should keep trying; the engine stops only on manual disconnect, background suspension, or zero subscriptions |

**Backoff reset condition** — backoff does **not** reset merely because the TCP/WebSocket handshake succeeded. It resets only when the connection proves useful: the first successfully decoded market event **or** the first successful heartbeat pong on the current generation, whichever comes first. Until then, a connect-then-immediately-drop cycle keeps escalating the delay. (The backend does send `subscribed`/`ack` control frames, but they are not guaranteed for every subscription, so the first-valid-event/pong condition is the strongest signal the current protocol supports.)

Manual `disconnect()` and background suspension cancel any scheduled reconnect and suppress future ones until `connect()`/foreground.

## Heartbeat

The backend protocol has no documented application-level ping, so the engine uses `URLSessionWebSocketTask` ping/pong via the transport (`sendPing`).

| Parameter | Default |
| --- | --- |
| Ping interval | 20 s after the last received message or pong |
| Pong timeout | 10 s |

- Pong received in time → heartbeat success counter, next ping scheduled.
- Timeout → heartbeat failure counter, connection is considered half-open, engine closes the transport and enters the reconnect path (one reconnect per timeout).
- Heartbeat timers are generation-tagged: a stale ping/pong/timeout callback from a previous generation is ignored.
- Manual disconnect and background suspension cancel the heartbeat.

## Event buffering, coalescing, and drop policy

All buffering state lives in the engine. Policies are **per event kind** — orderbook/trade/candle events are deliberately *not* treated like tickers:

| Event kind | Policy | Rationale |
| --- | --- | --- |
| Connection state | Never coalesced, never silently dropped | Consumers rely on ordering (`connecting` → `connected`) for UI status |
| Ticker | Coalesced to the **latest value per market identity** (exchange + symbol + quote) between consumer drains; preserves latest price, latest timestamp, generation, market identity | Only the newest price matters for UI; bursts must not queue N main-actor hops |
| Orderbook | Latest snapshot **replaces** any pending snapshot for the same market | The backend sends full snapshots; an outdated snapshot has no value |
| Trades | Appended in order; pending trade events per market bounded to the most recent 64 batches, oldest dropped **with the drop counted** | Recent-trades UI shows a short tail; unbounded queuing is worse than losing the oldest batch |
| Candles | Merged by (interval, candle timestamp): a newer update for the same candle replaces the pending one | Matches existing `mergeCandleUpdate` semantics in the view model |

Backstop: each consumer's pending buffer is engine-owned and bounded at capacity **1024**; on overflow the oldest non-connection-state event is dropped first (state events are dropped only as a last resort). In steady state coalescing keeps the pending set far below this; the backstop only trips if a consumer stalls entirely. All drops are counted in metrics (`explicitly dropped events`) — including events still pending when a consumer unregisters, so the conservation invariant (decoded = emitted + coalesced + dropped) holds at every point and nothing is dropped silently. Connection-state events can only be lost to a fully stalled or departing consumer, which is recorded and surfaced in the Pipeline Lab.

## Lifecycle policy

| Event | Behavior |
| --- | --- |
| App foreground | Resume: if ≥1 subscription, reconnect (new generation) and replay subscriptions once |
| App inactive | No action (transient state, e.g. system sheets) |
| App background | Suspend: close transport, cancel reconnect + heartbeat, **keep** the subscription registry so foreground can restore |
| Scene restoration | Same as foreground (adapter re-attaches, registry intact) |
| Manual logout | Public stream unaffected (it carries no credentials); private feed handling is unchanged legacy behavior |
| Zero subscriptions | Transport closed; no idle socket is kept alive |

This is stricter than the legacy service (which left the socket open in background and relied on the OS to kill it); the change is internal — no visible UI behavior depends on background socket liveness.

## UI adapter and migration path

`MarketStreamUIAdapter` implements the legacy `PublicWebSocketServicing` protocol verbatim (`connect()`, `disconnect()`, `updateSubscriptions(Set)`, plus the five callback closures), delivering all callbacks on `MainActor`. `CryptoViewModel` keeps its existing binding code (`bindPublicWebSocket`) unchanged; only its default service instance changes to the adapter.

Deprecation path: the legacy public `WebSocketService` is marked deprecated and kept compiling for reference/tests; once the private feed migrates to the engine, both legacy classes and the closure-based protocol can be retired in favor of direct `AsyncStream` consumption.

## Metrics

`RealtimeMetricsSnapshot` (all in-memory, no PII, no raw payloads):

connection state, generation, connection start time and uptime, active/upstream subscription counts, messages received/decoded/emitted, decode failures, tickers coalesced, explicitly dropped events, reconnect count, consecutive reconnect failures, last reconnect reason, heartbeat success/failure counts, latest event latency (transport receive → emission), rolling p50/p95 latency (fixed 256-sample ring buffer), maximum observed buffer usage.

Memory is bounded by construction: counters are scalars; the latency ring buffer is fixed-size; no payloads or identifiers are retained.

## Observability

- `os.Logger` categories: `realtime.connection`, `realtime.subscription`, `realtime.message`, `realtime.heartbeat`, `realtime.performance`; privacy annotations on all dynamic values; per-message logging only in DEBUG sampled form — normal operation logs transitions and counters, never every ticker.
- `OSSignposter` intervals: socket connect start/end, subscription reconciliation, first valid market event, reconnect recovery.

## Diagnostics: Realtime Pipeline Lab (DEBUG only)

`Cryptory/Views/Debug/RealtimePipelineLabView.swift` shows the metrics snapshot (state, subscriptions, uptime, counters, latency percentiles, reconnect/heartbeat health, buffer utilization) and offers simulation actions (forced connection failure, heartbeat timeout, rapid subscription replacement, fixture replay). The screen and its controls are compiled only under `#if DEBUG` and never reach Release builds; simulations act on the local engine only and cannot touch production users or credentials.

## Deterministic testing

See [TEST_STRATEGY.md](TEST_STRATEGY.md): a `ScriptedWebSocketTransport` and an injected manual clock drive every scenario (generation checks, refcounting, backoff bounds, heartbeat timeouts, coalescing, bounded buffers, malformed input, 100k-event replay) without live networking or wall-clock sleeps.
