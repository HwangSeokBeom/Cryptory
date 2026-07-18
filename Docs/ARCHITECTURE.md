# Architecture

This document describes the current architecture of the Cryptory iOS app honestly — including its legacy concentrations — and the boundaries this branch introduces. It is written for an iOS reviewer who wants to understand ownership, isolation, and the migration strategy in a few minutes.

Last updated: 2026-07-18 (branch `refactor/portfolio-realtime-foundation`)

## High-level shape

```mermaid
flowchart TB
    APP[CryptoryApp @main<br/>+ AppDelegate: Firebase, APNS] --> CV[ContentView<br/>owns the single CryptoViewModel]
    CV --> TABS[5 tabs: Market · Chart · News · Portfolio · Kimchi]
    CV --> VM[CryptoViewModel<br/>@MainActor ObservableObject]
    VM --> REPOS[Repository protocols<br/>LiveMarket/Trading/Portfolio/Kimchi/Connections/Auth]
    VM --> RT[Realtime services<br/>public: MarketStreamEngine via adapter<br/>private: PrivateWebSocketService legacy]
    VM --> KC[KeychainAuthSessionStore]
    REPOS --> API[APIClient + AppRuntimeConfiguration]
```

## Layers and ownership

| Layer | Types | Notes |
| --- | --- | --- |
| Entry | `CryptoryApp` (`Cryptory/CryptoryApp.swift`), `AppDelegate` | Firebase bootstrap, push registration, Apple sign-in bundle assertion |
| Root UI | `ContentView` | Owns the single `@StateObject CryptoViewModel`; custom header + `TabView`; login/connections/profile sheets |
| View model | `CryptoViewModel` (`Cryptory/ViewModels/CryptoViewModel.swift`) | `@MainActor final class`, ~20,235 lines, 114 `@Published` properties. Owns all screen state, market caches, task handles, and the auth flow |
| Repositories | `Cryptory/Services/NetworkService.swift` (~4.6k lines) | Protocol-first: `MarketRepositoryProtocol`, `TradingRepositoryProtocol`, `PortfolioRepositoryProtocol`, `KimchiPremiumRepositoryProtocol`, `ExchangeConnectionsRepositoryProtocol`, `AuthenticationServiceProtocol`, `MarketSnapshotCacheStoring` with `Live*` implementations |
| HTTP | `APIClient` + `AppRuntimeConfiguration` | Env-driven base URLs; production defaults to HTTPS/WSS, checked by a DEBUG-only assertion (`assertProductionTransportSecurity`) plus ATS in Release |
| Realtime | `Cryptory/Services/Realtime/` (new) + `Cryptory/Services/WebSocketService.swift` (legacy) | See [REALTIME_PIPELINE.md](REALTIME_PIPELINE.md) |
| Session | `AuthSession`, `KeychainAuthSessionStore` (`Cryptory/Models/AuthSession.swift`) | Keychain service `com.cryptory.auth.session`, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` |
| Logging | `AppLogger` (`Cryptory/Services/AppLogger.swift`) | `print`-based with token masking; realtime code adds `os.Logger` categories (this branch) |

## Dependency injection

Constructor injection with live defaults: `CryptoViewModel.init` accepts every dependency as an optional protocol parameter defaulting to `nil`, then resolves concrete `Live*` implementations internally. There is no DI container and no `@EnvironmentObject`; the single view-model instance is passed to child views by constructor argument. Test doubles (`CryptoryTests/TestDoubles.swift`) exploit the same seams.

A small number of singletons exist alongside (`PushNotificationService.shared`, `LiveGoogleSignInProvider.shared`, image/sparkline caches).

## The acknowledged god object

`CryptoViewModel` concentrates the state of every screen. This is a known liability, not a design goal. The migration strategy is deliberate:

1. **Do not** big-bang rewrite it (high regression risk against ~180 existing state-transition tests and live App Review work).
2. Extract *infrastructure* first behind existing protocols — this branch does that for the public realtime pipeline: the view model still talks to `PublicWebSocketServicing`, but the default implementation is now an adapter over an actor-isolated engine.
3. Extract *features* later, one tab at a time, once infrastructure seams are stable (market list first — see README roadmap).

## Realtime boundary (this branch)

The public market stream was rebuilt as an actor-isolated pipeline (`Cryptory/Services/Realtime/`). Key ownership rules:

- **`MarketStreamEngine` (actor)** is the only owner of connection state, socket generation, subscriptions, reconnect/heartbeat state, buffers, and metrics.
- **`WebSocketTransport` (protocol)** isolates `URLSessionWebSocketTask`; the engine never sees URLSession types, tests use a scripted transport.
- **`MarketStreamUIAdapter`** consumes the engine's `AsyncStream` and delivers on `MainActor`, implementing the legacy `PublicWebSocketServicing` protocol verbatim so `CryptoViewModel` and every screen remain behaviorally unchanged.
- The **private** trading socket (`PrivateWebSocketService`) intentionally still uses the legacy implementation; migrating it is a documented follow-up, not silently included here.

Rationale, alternatives, and consequences: [ADR 0001](ADR/0001-actor-isolated-realtime-engine.md).

## Concurrency model

- UI state: `@MainActor` (`CryptoViewModel` and SwiftUI views).
- Realtime: actor isolation (`MarketStreamEngine`); events cross to the main actor exactly once, in the adapter.
- App target builds with `SWIFT_VERSION = 6.0` and `SWIFT_APPROACHABLE_CONCURRENCY = YES`.
- Remaining `@unchecked Sendable` in the app target is documented in [SECURITY_AND_PRIVACY.md](SECURITY_AND_PRIVACY.md) and ADR 0001; the new realtime path introduces none (any exception is documented at the declaration).

## Deployment-target audit (iOS 26.0)

The project sets `IPHONEOS_DEPLOYMENT_TARGET = 26.0` at the project level and in the unit-test target; the app and UI-test targets inherit the project value.

- **History:** the project was created with the tooling-default `26.4` (the local Xcode's SDK version at creation time), not a documented product decision. GitHub-hosted runners with Xcode 26.3 exposed no simulator runtime satisfying 26.4, so `xcodebuild -showdestinations` returned only placeholder destinations and CI could not run (GitHub Actions run #29653999898).
- **Audit for 26.0:** the only OS-gated APIs in the codebase are the Apple Translation APIs in `TranslationService.swift`, already guarded with `@available(iOS 26.0, *)` / `#available(iOS 26.0, *)`. No source references any 26.1–26.4 API; all package dependencies have minimums far below iOS 26. Swift's compiler-enforced availability checking (plus `CLANG_WARN_UNGUARDED_AVAILABILITY = YES_AGGRESSIVE`) makes a clean build at 26.0 the exhaustive check.
- **Policy:** iOS 26.0 is the supported baseline — the intended iOS 26 design generation, forward-compatible with every 26.x runtime, and not tied to any single patch-level simulator runtime on CI. Raising the target requires a real API need documented here.

## Environment configuration

- Debug/Dev (`Configurations/Debug-Dev.xcconfig`): local backend `http://127.0.0.1:3002`, `ws://…`; only reachable when the developer explicitly runs the `Cryptory-Dev` scheme.
- Release/Prod (`Configurations/Release-Prod.xcconfig`): HTTPS/WSS production endpoints; a DEBUG-only assertion flags non-secure production schemes, and ATS constrains Release transport.
- Optional uncommitted `LocalSecrets.xcconfig` / `AuthSecrets.xcconfig` includes for machine-local overrides.
