# Performance Baseline

This document holds measured performance values for the realtime pipeline — and only measured values. Anything not yet measured is explicitly marked UNVERIFIED rather than estimated. At this stage of the branch, almost nothing has been measured; this file therefore functions primarily as the methodology and the template that the replay benchmark will fill in.

Last updated: 2026-07-18 (branch refactor/portfolio-realtime-foundation)

## 1. Purpose

Provide an honest before/after record for the realtime refactor (legacy `Cryptory/Services/WebSocketService.swift` → actor-isolated engine in `Cryptory/Services/Realtime/`). Numbers appear here only after being produced by the reproducible method in section 5. No throughput, latency, or memory claim in this repository should exist outside this file.

## 2. Environment template

| Field | Value |
| --- | --- |
| Machine | UNVERIFIED (to be recorded at measurement time) |
| OS | macOS (Darwin 25.4.0) |
| Xcode | 26.6 (17F113) |
| Simulator / runtime | UNVERIFIED (to be recorded; iOS 26.3–26.5 runtimes installed) |
| Build configuration | UNVERIFIED (to be recorded; expected Debug-Dev for test-based runs) |

## 3. Baseline before refactor

UNVERIFIED — the legacy `WebSocketService` has no injectable transport or clock, so a deterministic replay benchmark of the legacy path was not available in this environment. No quantitative baseline numbers exist for the legacy pipeline.

Only qualitative characteristics of the legacy path are recorded, from code inspection:

| Characteristic | Source |
| --- | --- |
| Per-message `DispatchQueue.main.async` dispatch on delivery | `WebSocketService.swift:513–530` (`parseMessage`) |
| No coalescing of burst updates; unbounded delivery | same delivery path |
| Double main-thread hop: main-queue dispatch, then ViewModel handlers re-wrap in `Task { @MainActor ... }` | `CryptoViewModel.swift:9348–9466` (`bindPublicWebSocket`) |

These are structural observations, not measurements; they motivate the metrics in section 4 but assert no numbers.

## 4. After refactor

To be produced by the replay benchmark (section 5). Every cell below is a placeholder until a measured run is pasted in.

| Metric | Value |
| --- | --- |
| Fixture | to be filled with measured values (fixture name/size) |
| Messages processed | to be filled with measured values |
| Elapsed (wall clock) | to be filled with measured values |
| Approx. throughput (msgs/s) | to be filled with measured values |
| Decoded count | to be filled with measured values |
| Emitted count | to be filled with measured values |
| Coalesced count | to be filled with measured values |
| Dropped count | to be filled with measured values |
| Reconnect count during run | to be filled with measured values |
| Measurement method / commit | to be filled with measured values |

## 5. Measurement method

- XCTest-based replay benchmark in `CryptoryTests/Realtime/` (being added on this branch; see `Docs/TEST_STRATEGY.md`).
- `ScriptedWebSocketTransport` feeds N scripted events (e.g. the high-volume 100k-event fixture) into the engine with no network involved.
- Wall-clock elapsed time is taken via `ContinuousClock` around the replay; counters (decoded/emitted/coalesced/dropped/reconnects) are read from the pipeline's diagnostics.
- Runs are repeated (report the run count with results); a single run is not a baseline.

## 6. Environmental limitations

- Simulator numbers are not device numbers. All values produced by the method above run on the iOS Simulator on a Mac; they characterize relative before/after behavior of the pipeline, not absolute device performance.
- Peak memory: UNVERIFIED — reliable peak-memory measurement was not available in this environment.
- Debug-configuration test builds include assertions and lack optimizations of Release builds; configuration must be recorded with every result row.

## 7. Future measurement work

Not yet implemented; listed as follow-ups, not capabilities:

- First-event latency (connect → first ticker emitted to the ViewModel).
- Reconnect recovery time (scripted failure → subscriptions replayed → first post-reconnect emission).
- Main-thread update counts via `os_signpost` instrumentation, to quantify the coalescing win over the legacy per-message double main-hop.
- MetricKit collection in the shipping app for field data (also listed as an observability gap in `Docs/INCIDENT_PLAYBOOK.md`).
