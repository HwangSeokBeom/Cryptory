# Cryptory

Cryptory is a SwiftUI iOS app for following the Korean crypto market in real time: multi-exchange market data (Upbit, Bithumb, Coinone, Korbit via a normalizing backend gateway), live charts with indicators, kimchi-premium comparison against a global reference price, news and community content, price alerts, and a read-only consolidated portfolio built from exchange API connections that never request trading or withdrawal permissions.

- Last updated: 2026-07-18 (branch `refactor/portfolio-realtime-foundation`)
- Marketing version: 1.0 (build 6)

## Features

| Area | What it does |
| --- | --- |
| Market | Multi-exchange market list with live tickers, search, favorites, sparklines |
| Chart | Candles, indicators, symbol comparison, live orderbook and recent trades |
| Kimchi premium | Korean-exchange price vs global reference price with FX conversion |
| News / community | Coin news, market trends, community posts, comments, votes |
| Portfolio | Read-only consolidated balances from connected exchange accounts |
| Alerts | Price alerts delivered via push notifications (FCM) |
| Auth | Google and Apple sign-in; session stored in the Keychain |

Supported exchanges (served through the app's own backend gateway, not direct exchange sockets): **Upbit, Bithumb, Coinone, Korbit**, plus a Binance reference price feed and an FX-rate provider for premium calculation.

## Read-only security policy

Exchange API connections are **read-only by product contract**. The app never asks users for API keys with trading or withdrawal permissions, never submits orders with real funds, and never processes exchange secrets on the device beyond the existing read-only connection flow. Details: [Docs/SECURITY_AND_PRIVACY.md](Docs/SECURITY_AND_PRIVACY.md).

## Screenshots

*(placeholders — assets to be added)*

| Market | Chart | Kimchi premium | Portfolio |
| --- | --- | --- | --- |
| _screenshot pending_ | _screenshot pending_ | _screenshot pending_ | _screenshot pending_ |

## Technology stack

- Swift 6 (app target), SwiftUI, structured concurrency (`async/await`, actors, `AsyncStream`)
- `URLSessionWebSocketTask` for real-time streams; `URLSession` for REST
- Firebase Messaging (push), GoogleSignIn-iOS, Sign in with Apple
- Keychain for session storage; `UserDefaults` for non-sensitive snapshot caches
- XCTest unit + UI tests; GitHub Actions CI (`.github/workflows/ios.yml`)
- Xcode 26.x, deployment target iOS 26.0

## Architecture summary

A single `@MainActor` `CryptoViewModel` (an acknowledged legacy god object, ~20k lines) owns screen state for five tabs and consumes protocol-injected repositories and services. New infrastructure is being extracted incrementally rather than big-bang rewritten; this branch introduces an actor-isolated real-time pipeline behind the existing service protocol so screens stay unchanged. Full details: [Docs/ARCHITECTURE.md](Docs/ARCHITECTURE.md) and [Docs/ADR/0001-actor-isolated-realtime-engine.md](Docs/ADR/0001-actor-isolated-realtime-engine.md).

## Real-time data flow

```mermaid
flowchart LR
    subgraph Exchanges
        UP[Upbit] & BT[Bithumb] & CO[Coinone] & KB[Korbit]
    end
    GW[Backend gateway<br/>normalized JSON envelope]
    UP & BT & CO & KB --> GW
    GW -- "wss /ws/market" --> TR[WebSocketTransport<br/>URLSessionWebSocketTransport]
    TR --> ENG["MarketStreamEngine (actor)<br/>generation checks · heartbeat ·<br/>reconnect backoff · refcounted subscriptions ·<br/>bounded buffers · metrics"]
    ENG -- "AsyncStream&lt;MarketStreamEvent&gt;" --> AD[MarketStreamUIAdapter<br/>MainActor delivery]
    AD -- "PublicWebSocketServicing callbacks" --> VM[CryptoViewModel<br/>@MainActor]
    VM --> UI[SwiftUI screens]
    GW -- "wss /ws/trading (private, unchanged)" --> PWS[PrivateWebSocketService] --> VM
```

Pipeline internals (buffering, coalescing, reconnect and heartbeat policies): [Docs/REALTIME_PIPELINE.md](Docs/REALTIME_PIPELINE.md).

## Build

Requirements: Xcode 26.x with an iOS 26.x simulator runtime.

```bash
git clone https://github.com/HwangSeokBeom/Cryptory.git
cd Cryptory
scripts/ci_build.sh              # unsigned simulator build, Cryptory-Dev scheme
# or open Cryptory.xcodeproj and run the Cryptory-Dev scheme
```

Schemes:

- `Cryptory-Dev` — Debug configuration, local development backend (HTTP/WS on localhost)
- `Cryptory-Prod` — Release configuration, production backend (HTTPS/WSS enforced)

## Test

```bash
# Unit tests run through the unit-only Cryptory-UnitTests scheme:
# build-for-testing, explicit simulator boot, smoke class, full suite —
# each phase watchdog-bounded (see Docs/TEST_STRATEGY.md §6).
scripts/ci_test.sh                                             # full unit flow
scripts/ci_test.sh test CryptoryTests/MarketStreamEngineTests  # focused realtime tests
scripts/verify_no_secrets.sh                                   # secret pattern scan
```

UI tests are separate — run them through the UI-capable `Cryptory-Dev` scheme (`xcodebuild test … -only-testing:CryptoryUITests`).

Strategy and coverage: [Docs/TEST_STRATEGY.md](Docs/TEST_STRATEGY.md).

## Environment configuration

- `Configurations/Debug-Dev.xcconfig` — Dev environment; points at a local backend (`http://127.0.0.1:3002`, `ws://…/ws/market`). Local HTTP/WS is allowed **only** in this explicitly selected Debug configuration.
- `Configurations/Release-Prod.xcconfig` — Prod environment; HTTPS/WSS by configuration. A DEBUG-build assertion (`AppRuntimeConfiguration.assertProductionTransportSecurity`) catches insecure production URLs during development, and App Transport Security constrains Release transport (the local-networking ATS exception exists only in the Dev Info.plist).
- Optional `Configurations/LocalSecrets.xcconfig` / `AuthSecrets.xcconfig` are `#include?`-d if present and are **not committed**.
- `server.env.example` documents the backend's expected environment variables with empty placeholders (the backend itself lives outside this repository).

## Implemented vs mocked vs planned

| Status | Item |
| --- | --- |
| Implemented | Market/chart/kimchi/news/community/portfolio/alerts features listed above; public and private WebSocket streams via backend gateway; Google/Apple sign-in; Keychain sessions |
| Implemented (this branch) | Actor-isolated public market stream engine, deterministic realtime test harness, CI baseline, DEBUG Realtime Pipeline Lab |
| Mocked / test-only | All network test doubles live in `CryptoryTests/TestDoubles.swift`; UI tests run against `UITestFixtureFactory` fixtures, not live servers |
| Planned (not implemented) | Private WebSocket migration to the actor engine; Crashlytics/MetricKit integration; CryptoViewModel feature-module decomposition; real trading (deliberately excluded — read-only policy) |

## Performance

Measured results (and explicit `UNVERIFIED` markers where measurement was not possible) are recorded in [Docs/PERFORMANCE_BASELINE.md](Docs/PERFORMANCE_BASELINE.md). This README intentionally makes no throughput or latency claims outside that document.

## Known limitations

- `CryptoViewModel` remains a ~20k-line single file; decomposition is deliberately out of scope for this branch (see ADR 0001).
- The private trading WebSocket still uses the legacy `@unchecked Sendable` implementation (documented follow-up).
- Deployment target iOS 26.0 restricts the app to iOS 26-generation devices; see [Docs/ARCHITECTURE.md](Docs/ARCHITECTURE.md) for the audit of that choice.
- CI requires a runner with any iOS 26.x simulator runtime; the workflow documents this baseline.
- No crash reporting (Crashlytics/MetricKit) is integrated yet.

## Roadmap

1. Migrate the private trading feed onto the actor-isolated engine.
2. Extract feature modules from `CryptoViewModel` incrementally (market list first).
3. Add MetricKit-based field performance/crash diagnostics.
4. Expand fixture-based replay coverage to orderbook depth and candle merge edge cases.

## Release status

App Store availability is not asserted here because it cannot be verified from this repository alone. The repository contains App Review-related working documents (`Docs/APP_REVIEW_REDESIGN_PLAN.md`, `Docs/ACCOUNT_DELETION_APP_REVIEW_CHECKLIST.md`) reflecting active review work.

## Documentation

| Doc | Contents |
| --- | --- |
| [Docs/ARCHITECTURE.md](Docs/ARCHITECTURE.md) | Layering, ownership, DI, legacy boundaries |
| [Docs/REALTIME_PIPELINE.md](Docs/REALTIME_PIPELINE.md) | Engine states, policies, buffering, metrics |
| [Docs/ADR/0001-actor-isolated-realtime-engine.md](Docs/ADR/0001-actor-isolated-realtime-engine.md) | Decision record for the realtime refactor |
| [Docs/TEST_STRATEGY.md](Docs/TEST_STRATEGY.md) | Test layers, doubles, deterministic realtime tests |
| [Docs/PERFORMANCE_BASELINE.md](Docs/PERFORMANCE_BASELINE.md) | Measured performance results only |
| [Docs/SECURITY_AND_PRIVACY.md](Docs/SECURITY_AND_PRIVACY.md) | Read-only policy, Keychain, logging rules, known gaps |
| [Docs/INCIDENT_PLAYBOOK.md](Docs/INCIDENT_PLAYBOOK.md) | On-call playbook for realtime/API/auth/push incidents |
