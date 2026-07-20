# Performance Baseline

This document holds measured performance values for the realtime pipeline — and only measured values. Anything not yet measured is explicitly marked UNVERIFIED rather than estimated.

Last updated: 2026-07-19 (branch refactor/portfolio-realtime-foundation)

## 1. Purpose

Provide an honest before/after record for the realtime refactor (legacy `Cryptory/Services/WebSocketService.swift` → actor-isolated engine in `Cryptory/Services/Realtime/`). Numbers appear here only after being produced by the reproducible method in section 5. No throughput, latency, or memory claim in this repository should exist outside this file.

## 2. Environment template

| Field | Value |
| --- | --- |
| Machine | Mac17,4 (Apple M5, 32 GB RAM) |
| OS | macOS 26.4.1 (25E253) |
| Xcode | 26.6 (17F113) |
| Simulator / runtime | iPhone 17e, iOS 26.5 |
| Build configuration | Debug (Cryptory-Dev scheme, XCTest run) |

## 3. Baseline before refactor

UNVERIFIED — the legacy `WebSocketService` has no injectable transport or clock, so a deterministic replay benchmark of the legacy path was not available in this environment. No quantitative baseline numbers exist for the legacy pipeline.

Only qualitative characteristics of the legacy path are recorded, from code inspection:

| Characteristic | Source |
| --- | --- |
| Per-message `DispatchQueue.main.async` dispatch on delivery | `WebSocketService.swift:513–530` (`parseMessage`) |
| No coalescing of burst updates; unbounded delivery | same delivery path |
| Double main-thread hop: main-queue dispatch, then ViewModel handlers re-wrap in `Task { @MainActor ... }` | `CryptoViewModel.swift:9348–9466` (`bindPublicWebSocket`) |

These are structural observations, not measurements; they motivate the metrics in section 4 but assert no numbers.

## 4. After refactor (measured)

Produced by `RealtimeReplayBenchmarkTests.testReplayThroughputHundredThousandMessages` (section 5), two runs on 2026-07-19 in the environment of section 2:

| Metric | Run 1 | Run 2 |
| --- | --- | --- |
| Fixture | multi-market high-volume, 100,000 ticker messages, 20 markets × 2 exchanges | same |
| Messages processed | 100,000 | 100,000 |
| Elapsed (feed start → fully decoded, wall clock) | 14.32 s | 14.07 s |
| Approx. throughput | 6,982 msgs/s | 7,107 msgs/s |
| Decoded count | 100,000 | 100,000 |
| Emitted count | 100,000 | 100,000 |
| Coalesced count | 0 (consumer kept up; max pending buffer = 2) | 0 |
| Explicitly dropped count | 0 | 0 |
| Decode failures | 0 | 0 |
| Reconnect count during run | 0 | 0 |
| Max consumer buffer usage | 2 | 2 |
| Emission latency p50 / p95 (buffer enqueue → dequeue) | 0.17 ms / 0.19 ms | 0.02 ms / 0.03 ms |
| First market event delivery latency (`testFirstMarketEventDeliveryLatency`) | 0.102 ms | 0.120 ms |

Notes on interpretation (honest limits):

- Single-consumer delivery conservation held in both runs: consumer-delivered + coalesced + counted drops = messages (valid because the benchmark registers exactly one consumer; see the counter groups in `Docs/REALTIME_PIPELINE.md`), i.e. nothing was silently lost.
- Coalescing shows 0 because the benchmark consumer drains continuously; the coalescing path is exercised and asserted separately by the deterministic tests (`testTickerCoalescingEmitsNewestValueForSlowConsumer`).
- Elapsed time includes the benchmark's own cooperative polling loop awaiting drain, so throughput is a conservative lower bound for the engine itself.
- Emission-latency percentiles vary between runs at the tens-of-microseconds level; treat them as order-of-magnitude, not precise.
- No comparable legacy number exists (section 3), so no before/after improvement is claimed — only the post-refactor measurements above.

## 5. Measurement method

- XCTest-based replay benchmark: `CryptoryTests/Realtime/RealtimeReplayBenchmarkTests.swift` (see `Docs/TEST_STRATEGY.md`).
- `ScriptedWebSocketTransport` feeds N scripted events (e.g. the high-volume 100k-event fixture) into the engine with no network involved.
- Wall-clock elapsed time is taken via `ContinuousClock` around the replay; counters (decoded/emitted/coalesced/dropped/reconnects) are read from the pipeline's diagnostics.
- Runs are repeated (report the run count with results); a single run is not a baseline.

## 6. Environmental limitations

- Simulator numbers are not device numbers. All values produced by the method above run on the iOS Simulator on a Mac; they characterize relative before/after behavior of the pipeline, not absolute device performance.
- Peak memory: UNVERIFIED — reliable peak-memory measurement was not available in this environment.
- Debug-configuration test builds include assertions and lack optimizations of Release builds; configuration must be recorded with every result row.

## 7. Future measurement work

Not yet implemented; listed as follow-ups, not capabilities:

- Reconnect recovery time (scripted failure → subscriptions replayed → first post-reconnect emission).
- Main-thread update counts via `os_signpost` instrumentation, to quantify the coalescing win over the legacy per-message double main-hop. (No signposts are implemented anywhere in the realtime path today.)
- MetricKit collection in the shipping app for field data (also listed as an observability gap in `Docs/INCIDENT_PLAYBOOK.md`).
