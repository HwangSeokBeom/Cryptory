# Real-Time Pipeline

This document specifies the actor-isolated public market stream pipeline introduced on this branch (`Cryptory/Services/Realtime/`): its state machine, ownership rules, buffering/coalescing policies, reconnect and heartbeat behavior, and metrics. The private trading socket is *not* covered — it still uses the legacy implementation (documented follow-up).

Last updated: 2026-07-19 (branch `refactor/portfolio-realtime-foundation`)

## Components

| Component | Kind | Responsibility |
| --- | --- | --- |
| `MarketStreamEngine` | `actor` | Sole owner of connection state, socket generation, subscription registry, reconnect/heartbeat state, event buffering, metrics |
| `WebSocketTransport` | protocol | Abstract socket: open a connection, send text, send ping, pull the next event via `receive()`, close. No URLSession types leak past it |
| `URLSessionWebSocketTransport` | struct/class | Production transport over `URLSessionWebSocketTask` |
| `MarketSubscriptionRegistry` | struct (engine-owned) | Reference-counted ownership of upstream subscriptions |
| `ReconnectPolicy` | struct | Exponential backoff parameters + delay computation |
| `HeartbeatPolicy` | struct | Ping cadence and timeout parameters |
| `MarketStreamDecoder` | enum/struct | Wire JSON → typed payloads (wraps the existing `MarketWebSocketMessageParser` contract) |
| `RealtimeMetrics` / `RealtimeMetricsSnapshot` | engine-owned / `Sendable` struct | Bounded in-memory counters and latency samples |
| `MarketStreamUIAdapter` | `@MainActor` class | Consumes the engine's `AsyncStream`, implements the legacy `PublicWebSocketServicing` protocol for `CryptoViewModel`; explicit idempotent `shutdown()` releases all ownership |

## Ownership and isolation rules

- Only the `MarketStreamEngine` actor mutates: connection state, active socket generation, reconnect attempt count, subscriptions, heartbeat state, buffering state, metrics counters.
- The transport never mutates UI state and never calls back into the engine except by delivering transport events into the engine's receive loop.
- Events leave the engine exclusively through `AsyncStream<MarketStreamEvent>`.
- The adapter is the only component that touches `MainActor`; SwiftUI types never appear in the engine or transport.
- The new path contains exactly one `@unchecked Sendable`: `URLSessionWebSocketTransportConnection`, the compatibility boundary around URLSession types (`URLSessionWebSocketTask` is not `Sendable`; the wrapper's shared state is mutex-guarded). It is documented at the declaration; nothing else in the new path uses `@unchecked Sendable`.

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

## Transport ingress (pull-based, bounded)

The transport is **pull-based**: the engine calls `receive()` for one event at a time and does not request the next frame until the current one has been accepted (decoded and dispatched or rejected as stale). `URLSessionWebSocketTransportConnection` keeps exactly one `URLSessionWebSocketTask.receive` outstanding, started only on demand, and its mailbox holds at most one text frame plus a fixed handful of control events (`opened`, `closed`, one terminal error). Consequences:

- there is **no app-side queue of raw, undecoded frames** anywhere between the socket and the decoder — pre-decode memory is bounded to a single frame by construction;
- no raw orderbook, trade, candle, or control frame is ever silently dropped at the transport layer (there is no transport-side overflow to drop from);
- producer pressure stays in the network/kernel buffers, where TCP flow control applies;
- closing the connection fails the pending `receive()`; no receive loop survives disconnect.

`ScriptedWebSocketTransport` models the identical contract in tests: its scripted queue represents the remote/network side, and assertions verify that at most one receive is ever outstanding, including under a 100k-message replay.

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

**Subscription changes during backoff** — while the engine is in `waitingToReconnect`, subscription replacement only reconciles the registry: it never cancels or resets the backoff timer, and no connection is opened early. When the timer fires, the final converged subscription set is replayed exactly once on the new generation. Only two things bypass the wait: the timer itself, and an explicit `connect()` call (a deliberate caller action, documented on the API). An empty subscription set during the wait cancels the pending reconnect entirely (zero-subscription policy).

**Sender ownership** — outbound sends are drained by a single sender task per connection, tagged with an ownership epoch. Teardown invalidates the epoch, so a stale sender resuming from a suspended `send` after teardown (URLSession may resume even after cancellation) can never clear the newer sender, drain a newer outbox, trigger idle close, or schedule reconnects for a newer generation.

**Idle-close convergence** — when the registry becomes empty the engine flushes pending unsubscribes and closes once the outbox drains; if a non-empty subscription set arrives before the drain completes (A → [] → B), the pending idle close is cancelled and the socket is kept for the new set — no reconnect is needed.

## Heartbeat

The backend protocol has no documented application-level ping, so the engine uses `URLSessionWebSocketTask` ping/pong via the transport (`sendPing`).

| Parameter | Default |
| --- | --- |
| Ping interval | 20 s, fixed cadence from connection open |
| Pong timeout | 10 s |

- Pings are sent on a fixed cadence: receiving market messages does **not** reset the ping timer (a successful decoded event does mark the connection useful for backoff purposes, but the next ping still fires on schedule).
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

Backstop: each consumer's pending buffer is engine-owned and bounded at capacity **1024**; on overflow the oldest non-connection-state event is dropped first (state events are dropped only as a last resort). In steady state coalescing keeps the pending set far below this; the backstop only trips if a consumer stalls entirely. All drops are counted in metrics — including events still pending when a consumer unregisters or its task is cancelled — so the delivery-side conservation equation below holds and nothing is dropped silently. Connection-state events can only be lost to a fully stalled or departing consumer, which is recorded and surfaced in the Pipeline Lab.

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

`MarketStreamUIAdapter` implements the legacy `PublicWebSocketServicing` protocol (`connect()`, `disconnect()`, `updateSubscriptions(Set)`, plus the five callback closures). The protocol's callbacks are declared `@MainActor` and the adapter invokes them on the main actor, so `CryptoViewModel` applies state synchronously inside the callback — there is no additional per-event `Task { @MainActor }` hop in the view model.

**Lifecycle and ownership release:**

- Cancelling a consumer's stream task releases engine-side ownership atomically: the waiter and buffer are removed (pending events become counted drops), registry ownership is released, upstream subscriptions reconcile, and the socket closes when the final owner leaves. This covers the window where cancellation lands before the waiter is installed; explicit `unregister` afterwards stays idempotent.
- The adapter's tasks do not retain the adapter across suspensions, so dropping the last strong reference deallocates it. The explicit, idempotent `shutdown()` is the teardown contract: it stops command intake, cancels the command and consumer tasks (releasing engine ownership as above), removes lifecycle observers, and stops callback delivery; `deinit` only runs the same cleanup as a nonblocking safety net.

Deprecation path: the legacy public `WebSocketService` is marked deprecated and kept compiling for reference/tests; once the private feed migrates to the engine, both legacy classes and the closure-based protocol can be retired in favor of direct `AsyncStream` consumption.

## Metrics

`RealtimeMetricsSnapshot` (all in-memory, no PII, no raw payloads) groups counters by pipeline stage so global and per-consumer quantities are never mixed:

- **Ingress (global):** `transportFramesReceived`, `messagesDecoded`, `controlMessages`, `decodeFailures`. Valid conservation: `transportFramesReceived == messagesDecoded + controlMessages + decodeFailures`. (There are no transport-level rejected/backpressured counters because the pull-based transport has no overflow to count — see the ingress section.)
- **Engine emission (global):** `logicalEventsEmitted` — one per logical `MarketStreamEvent` dispatched (market events and connection-state events), independent of consumer count.
- **Delivery (aggregated across consumers):** `consumerEnqueues`, `consumerDeliveries`, `tickerEventsCoalesced`, `orderbookSnapshotsReplaced`, `candleUpdatesMergedOrReplaced`, `tradeEventsDropped` (per-market trade bound), `bufferEventsDropped` (capacity backstop plus unregister/cancellation discards). Valid conservation at any quiescent point: `consumerEnqueues == consumerDeliveries + tickerEventsCoalesced + orderbookSnapshotsReplaced + candleUpdatesMergedOrReplaced + tradeEventsDropped + bufferEventsDropped + (events still pending in live consumer buffers)`.
- Connection health: reconnect count, consecutive reconnect failures, last reconnect reason, heartbeat success/failure counts.
- Latency: latest event latency (buffer enqueue → consumer dequeue), rolling p50/p95 (fixed 256-sample ring buffer), maximum observed buffer usage.

Global decoded counts must never be compared against per-consumer delivery counts — with N consumers, one decoded event fans out N times; the Pipeline Lab labels the two groups separately for this reason.

Memory is bounded by construction: counters are scalars; the latency ring buffer is fixed-size; no payloads or identifiers are retained.

## Observability

- `os.Logger` categories: `realtime.connection`, `realtime.subscription`, `realtime.message`, `realtime.heartbeat`, `realtime.performance`; privacy annotations on all dynamic values; per-message logging only in DEBUG sampled form — normal operation logs transitions and counters, never every ticker.

## Diagnostics: Realtime Pipeline Lab (DEBUG only)

`Cryptory/Views/Debug/RealtimePipelineLabView.swift` shows the metrics snapshot (state, subscriptions, uptime, counters, latency percentiles, reconnect/heartbeat health, buffer utilization) and offers simulation actions (forced connection failure, heartbeat timeout, rapid subscription replacement, fixture replay). The screen and its controls are compiled only under `#if DEBUG` and never reach Release builds; simulations act on the local engine only and cannot touch production users or credentials.

## Deterministic testing

See [TEST_STRATEGY.md](TEST_STRATEGY.md): a `ScriptedWebSocketTransport` and an injected manual clock drive every scenario (generation checks, refcounting, backoff bounds, heartbeat timeouts, coalescing, bounded buffers, malformed input, 100k-event replay) without live networking or wall-clock sleeps.
