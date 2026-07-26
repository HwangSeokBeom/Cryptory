# Incident Playbook

An on-call playbook for the incident classes this app can realistically hit: realtime feed outages, backend REST outages, auth/session failures, push delivery failures, and App Store review-critical regressions. Each section lists symptoms, immediate checks, diagnosis, mitigation, and post-incident actions grounded in the actual client code paths. It also states plainly what observability does not exist yet.

Last updated: 2026-07-18 (branch refactor/portfolio-realtime-foundation)

## Severity matrix

| Severity | Definition | Examples |
| --- | --- | --- |
| SEV1 | Core product unusable for most users, or user trust/data at risk | Backend REST + WS both down; auth completely broken; account deletion broken while an App Review is in flight |
| SEV2 | Major feature degraded, workaround exists | Public WS down but REST polling fallback serving stale-but-updating prices; private feed down with 7s polling |
| SEV3 | Single feature or single exchange degraded | One upstream exchange feed stale; kimchi premium FX source failing; push delivery delayed |
| SEV4 | Cosmetic or low-impact | Stale sparkline, one-off parse drop of a malformed message |

## Escalation checklist

1. Confirm scope: one exchange, one feed (public/private), or whole backend? Reproduce in the app (Dev scheme against prod URLs if needed).
2. Check the backend gateway host (`https://cryptory.duckdns.org`) for REST reachability, then the WS endpoints (`/ws/market`, `/ws/trading`).
3. Check upstream exchange status pages (Upbit, Bithumb, Coinone, Korbit) — the gateway normalizes all of them into one envelope, so a single-exchange outage is upstream, not gateway.
4. Classify severity with the matrix above; note start time.
5. Mitigate (sections below), then write up post-incident actions.

Honest limitation: there is currently no crash reporting (no Crashlytics; only FirebaseMessaging is linked from firebase-ios-sdk) and no server-side alerting is documented in this repo. Detection today is user reports and manual checks. See "Observability gaps" at the end.

## (a) Public market WebSocket outage / degradation

The backend gateway exposes a single public socket at `/ws/market` that normalizes all exchanges into one JSON envelope. The production client is the actor-isolated `MarketStreamEngine` behind `MarketStreamUIAdapter` (`Cryptory/Services/Realtime/`). The legacy `WebSocketService` is deprecated and no longer used for the public path; only the private trading socket still runs on the legacy `PrivateWebSocketService` implementation (documented follow-up).

- Symptoms in-app: prices stop ticking on the market/chart tabs; `publicWebSocketState` leaves `.connected`; the ViewModel derives `StreamingStatus.pollingFallback` when the state is `.disconnected`/`.failed` and surfaces a streaming warning. The engine sends a protocol-level ping every 20 s with a 10 s pong timeout, so a half-open connection is detected within ~30 s and enters the reconnect path (`heartbeat timeout` appears as the disconnect reason in the Pipeline Lab and `realtime.heartbeat` logs).
- Immediate checks: can you open a WS connection to `wss://cryptory.duckdns.org/ws/market`? Is REST (`/`) still answering? Are all exchanges stale or just one?
- Diagnosis: all-exchange staleness on one socket implies gateway outage; single-exchange staleness implies upstream exchange outage behind the gateway (check exchange status pages / gateway server logs — server-side, outside this repo).
- Client behavior during outage: the engine schedules reconnects with exponential backoff (1 s initial, ×2, 30 s cap, ±20 % jitter); backoff resets only once a connection proves useful (first decoded event or pong). Subscription churn during the wait reconciles the registry without resetting backoff, and the converged set is replayed exactly once on reconnect. Separately, the ViewModel activates a REST polling fallback (`updatePublicPollingIfNeeded`) that polls tickers/chart data every 5 seconds (8 seconds on the kimchi tab) while status is `.pollingFallback`.
- Mitigation: restore the gateway (server-side). Client-side, users still get 5s-granularity data via the polling fallback; no client release is required for a pure backend outage. Foregrounding the app retriggers connects (`onScenePhaseChanged` acts on `.active`, `CryptoViewModel.swift:4413–4438`).
- Post-incident: record duration; jittered exponential backoff prevents a synchronized thundering herd on recovery. Verify subscription replay restored all channels (one `subscribe` per active subscription on the new generation) via the Pipeline Lab counters.

## (b) Private trading feed outage

Private socket `/ws/trading` (`PrivateWebSocketService`, `WebSocketService.swift:555`), authenticated, feeds portfolio/orders/fills.

- Symptoms: portfolio balances and open orders stop updating; `privateWebSocketState` is `.connecting`/`.disconnected`/`.failed` — all three map to `.pollingFallback` (`CryptoViewModel.swift:19004–19013`).
- Immediate checks: is the public feed also down (gateway-wide) or only private (auth/token path)? Is the user's session valid (a 401 on REST points to auth, not the feed)?
- Client behavior: the private client reconnects with exponential backoff, 2s doubling to a 30s cap (`privateReconnectDelay`, `WebSocketService.swift:697–699`); the failure counter resets on any successful receive or send (`:674`, `:728`). The ViewModel polls portfolio/orders every 7 seconds while degraded (`updatePrivatePollingIfNeeded`, `CryptoViewModel.swift:10053–10086`).
- Mitigation: server-side restore; client keeps 7s polling. If the cause is token expiry, the refresh flow (section d) reconnects the feed on success (`connectPrivateTradingFeedIfNeeded(reason: "refresh_success")`, `CryptoViewModel.swift:7274`).
- Post-incident: check whether degraded polling put meaningful extra load on REST endpoints; confirm no private payloads were logged.

## (c) Backend REST API outage

All REST goes through `APIClient` and the `Live*Repository` types in `Cryptory/Services/NetworkService.swift`.

- Symptoms: initial loads fail, pull-to-refresh errors, and — critically — the WS polling fallbacks (a) and (b) also fail, so the app degrades to cached snapshots (`UserDefaultsMarketSnapshotCacheStore`, `NetworkService.swift:846`) and error states.
- Immediate checks: `curl https://cryptory.duckdns.org/...` for a known endpoint; distinguish DNS (DuckDNS), TLS certificate expiry, and application-level 5xx.
- Diagnosis: `NetworkServiceError` categories distinguish transport errors, HTTP status errors, and parsing failures; parsing failures on 200s indicate a backend contract regression rather than an outage.
- Mitigation: server-side. Client-side, verify cached market snapshots render rather than blank screens.
- Post-incident: if the cause was a contract change, add/extend a parsing test in `CryptoryTests/NetworkAndAuthTests.swift`.

## (d) Auth / session incidents

Session lifecycle lives in `CryptoViewModel` (`Cryptory/ViewModels/CryptoViewModel.swift:7203–7329`) with Keychain persistence (`KeychainAuthSessionStore`, `Cryptory/Models/AuthSession.swift:84–215`).

- Symptoms: users bounced to the login sheet; portfolio/trade tabs gated; repeated `[AuthFlowDebug] action=refresh_failed` in Debug logs.
- Client behavior, refresh: an authenticated request that fails with 401/`authenticationFailed` triggers exactly one refresh attempt and a retry (`runAuthenticatedRequest`, `:7203–7220`); concurrent refreshes are coalesced through a single `sessionRefreshTask` (`:7255–7264`); on success the new session is saved to the Keychain and the private feed reconnects.
- Client behavior, forced logout: a refresh failure with HTTP 400/401/403 or `authenticationFailed` clears the local session (`shouldClearSessionAfterRefreshFailure`, `:7308–7321` → `expireSessionAfterRefreshFailure`, `:7323–7329`), resets protected UI state, and presents login if the user is on a protected tab. Transport errors do not force logout — offline users keep their session.
- Immediate checks: is the failure a backend auth-service outage (5xx on refresh — clients will not mass-logout, by design) or token invalidation (401/403 — clients will mass-logout)? Are Google/Apple sign-in endpoints resolving (`AppLogger.authConfiguration` prints them at startup)?
- Mitigation: for accidental server-side token invalidation, restoring the backend lets users sign in again; the client requires no release. Verify logout cleanup ran (`PushNotificationService.shared.cleanupForLogout`, `:6977`).
- Post-incident: confirm no tokens appeared in logs (rules in `Docs/SECURITY_AND_PRIVACY.md`); consider alerting on refresh-failure rate server-side (not currently in place).

## (e) Push notification delivery failures

Price alerts are delivered via FCM (`firebase-ios-sdk`, pinned 12.12.1; `Cryptory/Services/PushNotificationService.swift`, registered in `AppDelegate`).

- Symptoms: price alerts not arriving; alert configured in-app but no notification fires.
- Immediate checks: device-level — notification permission granted? Token issued (`[Push] fcm token received exists=true length=...`, `PushNotificationService.swift:165`, Debug builds)? Server-side — is the backend actually sending to FCM; is the APNs auth key valid in the Firebase project?
- Diagnosis order: device permission → FCM token registration with backend → backend alert-evaluation job → FCM/APNs delivery. Note FCM delivery is best-effort; isolated delays are not incidents.
- Mitigation: mostly server-side (re-send, fix APNs credentials). Client-side, sign-out/sign-in re-registers the token (logout runs `cleanupForLogout`).
- Post-incident: verify tokens were never logged in full (length-only logging is the current rule).

## (f) App Store review-critical regressions

Two review-sensitive areas have dedicated docs in this repo: `Docs/ACCOUNT_DELETION_APP_REVIEW_CHECKLIST.md` and `Docs/APP_REVIEW_REDESIGN_PLAN.md` (the latter covers the guideline 3.1.5(iii) redesign for cryptocurrency-app constraints).

- Symptoms: rejection notice from App Review, or a regression found in the account-deletion flow (client entry point: `deleteAccount(session:)` in `AuthenticationServiceProtocol`, path configured as `/account`, `Cryptory/Services/NetworkService.swift:930–1112`).
- Immediate checks before any submission: account deletion completes end-to-end (delete → session cleared → login required); app behavior matches the 3.1.5(iii) constraints documented in `Docs/APP_REVIEW_REDESIGN_PLAN.md`; login works for the review account (a prior release, commit `03a985a3` / `9b20da44`, fixed App Review login and news issues — treat that area as regression-prone).
- Mitigation: a review-blocking regression is SEV1 during an active review window; fix, bump the build number, and resubmit. Do not ship changes to gated/trading-adjacent UI without re-reading the two review docs above.
- Post-incident: update the checklist docs with whatever the rejection taught.

## Observability gaps (honest status)

| Gap | Status | Follow-up |
| --- | --- | --- |
| Crash reporting | Not present. No Crashlytics (only FirebaseMessaging linked), no MetricKit collection. | MetricKit and/or Crashlytics integration is documented follow-up work, not implemented. |
| Server-side alerting | Not documented anywhere in this repo. | Document backend alerting (gateway WS connection counts, refresh-failure rate, FCM send failures). |
| Client heartbeat / staleness detection | Public socket: implemented — the engine pings every 20 s (10 s pong timeout) and reconnects on heartbeat timeout, covered by deterministic tests. Private socket: still no heartbeat on the legacy implementation. | Migrate the private trading socket to the engine (documented follow-up). |
| Structured logging | Legacy `AppLogger` is print-based; only the realtime pipeline (`RealtimeLog` categories `realtime.*`) writes to unified logging for sysdiagnose triage. | Migrate the rest of `AppLogger` to `os.Logger` (follow-up). |
