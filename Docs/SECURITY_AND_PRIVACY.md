# Security and Privacy

This document describes the security- and privacy-relevant design decisions actually implemented in the Cryptory iOS client, with file references, and an honest list of known gaps. It intentionally avoids absolute claims: the measures below reduce specific risks; they do not make the app "secure" in any absolute sense.

Last updated: 2026-07-18 (branch refactor/portfolio-realtime-foundation)

## 1. Read-only exchange API connection policy

Cryptory connects to Korean exchanges (Upbit, Bithumb, Coinone, Korbit; Binance is used only as a reference price for the kimchi premium) exclusively through the project's backend gateway. The policy is:

- Exchange API connections are read-only. The app requests no trading or withdrawal permissions for connected exchange accounts; connections exist to read balances, orders, and fills for the consolidated portfolio.
- Exchange API credentials are stored server-side, never on the device. `server.env.example` documents the backend design: per-exchange access/secret keys (`UPBIT_ACCESS_KEY`, `BITHUMB_SECRET_KEY`, `COINONE_ACCESS_TOKEN`, `KORBIT_API_KEY`, etc.) live in the server environment, and `EXCHANGE_CREDENTIAL_ENCRYPTION_KEY` designates a 32-byte key for encrypting user-supplied exchange credentials at rest on the server. The template contains empty placeholders only; no real credentials are committed.
- The iOS client talks to the backend through the repositories in `Cryptory/Services/NetworkService.swift` (e.g. `ExchangeConnectionsRepositoryProtocol`); it never signs exchange API requests itself and never holds exchange keys.

## 2. Session storage (Keychain)

Auth sessions (access/refresh tokens) are persisted in the iOS Keychain, not in `UserDefaults` or files.

| Aspect | Value | Source |
| --- | --- | --- |
| Store | `KeychainAuthSessionStore` | `Cryptory/Models/AuthSession.swift` (lines 84–215) |
| Keychain service | `com.cryptory.auth.session` | `AuthSession.swift:85` |
| Accessibility | `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` | `AuthSession.swift:199` |

`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` means the session is unreadable before the first device unlock after boot and is excluded from device-to-device backups/restores (this-device-only), which limits token exfiltration via backups.

## 3. Token and PII logging rules

Legacy logging goes through `enum AppLogger` (`Cryptory/Services/AppLogger.swift`, print-based — see gaps). The new realtime pipeline logs through `os.Logger` (`RealtimeLog` in `Cryptory/Services/Realtime/MarketStreamEngine.swift`) with privacy annotations; it logs states, generations, and counters — never payloads or identifiers.

- `AppLogger.debug` / `debugOnce` are compiled out of Release builds (`#if DEBUG`).
- `AppLogger.masked(_:)` reduces a value to first 3 + last 2 characters (fully starred at 6 characters or fewer); `sanitizedMetadata(_:)` automatically masks any metadata key containing `secret`, `token`, `access`, or `key`.
- FCM tokens are logged by length only, never by value: `"[Push] fcm token received exists=true length=..."` (`Cryptory/Services/PushNotificationService.swift:165`).
- Auth flow logs record booleans (`hasAccessToken`, `hasRefreshToken`), not token contents (`Cryptory/ViewModels/CryptoViewModel.swift`, `[AuthFlowDebug]` entries).

Must never be logged, in any build configuration:

| Never log | Notes |
| --- | --- |
| Access / refresh tokens | Log presence booleans or `masked(...)` only |
| Authorization headers | Including `Bearer ...` values |
| Exchange API keys / secrets | Should never reach the client at all |
| Apple / Google identity tokens | OAuth/OIDC assertions |
| Full FCM / APNs tokens | Length or masked form only |
| Raw private WebSocket payloads | Contain balances, orders, fills |
| Emails and other PII | User identifiers, names |

## 4. Transport security

Runtime endpoints are resolved by `AppRuntimeConfiguration` (`Cryptory/Services/NetworkService.swift:247–476`):

- Production (`Configurations/Release-Prod.xcconfig`) defaults to `https://cryptory.duckdns.org` (REST/web) and `wss://cryptory.duckdns.org` (WebSocket, paths `/ws/market` and `/ws/trading`).
- `isATSSafe` (`NetworkService.swift:460–465`) verifies all four resolved URLs use `https`/`wss`; `assertProductionTransportSecurity()` (`:467–475`) raises an `assertionFailure` if a production-environment build resolves to plaintext schemes. Note this assertion is `#if DEBUG`-gated, so it catches misconfiguration during development but is compiled out of Release binaries (see gaps).
- Development (`Configurations/Debug-Dev.xcconfig`) uses plain `http/ws` against `127.0.0.1:3002` only. `Cryptory/Info-Dev.plist` enables `NSAllowsLocalNetworking` for this; the production `Info.plist` carries no such exception.

## 5. Secrets handling in the repo

- `Configurations/Debug-Dev.xcconfig` ends with optional includes `#include? "LocalSecrets.xcconfig"` and `#include? "AuthSecrets.xcconfig"`. These files are not committed (and `.gitignore` covers `.env` / `.env.*` patterns); they exist for per-developer overrides such as LAN device IPs.
- `GOOGLE_CLIENT_ID` / `GOOGLE_REVERSED_CLIENT_ID` are committed in both xcconfigs. This is acceptable by design: OAuth 2.0 client IDs for native apps are public identifiers, not secrets — they are necessarily embedded in every shipped binary and in the app's URL scheme, and are recoverable from any installed copy of the app. Security does not rest on their confidentiality; it rests on bundle-ID/redirect validation and on server-side verification of the identity tokens Google issues.
- `server.env.example` is a placeholder-only template; real backend secrets are never committed.

## 6. Known gaps

This section lists real, currently unresolved issues. They are documented rather than hidden.

| Gap | Detail | Risk assessment | Remediation options |
| --- | --- | --- | --- |
| `GoogleService-Info.plist` is tracked in git | `Cryptory/GoogleService-Info.plist` is committed; the `.gitignore` rule (line 28) was added after the file was already tracked, and gitignore does not untrack existing files. | Low-to-moderate. The file contains Firebase project identifiers and an API key that identify the Firebase project rather than granting account access (Google's documentation treats its presence in shipped apps as expected — it is extractable from any distributed IPA regardless). Residual risks are quota abuse and project enumeration. | `git rm --cached Cryptory/GoogleService-Info.plist` plus a local-copy build step; and/or apply API-key application restrictions in the Google Cloud console; verify Firebase security rules assume the config is public. |
| Unconditional Release logging | `AppLogger.configuration` and `AppLogger.authConfiguration` call `print` without a `#if DEBUG` guard (`AppLogger.swift:33–39`), so environment, resolved base URLs, and social-auth endpoints are printed in Release builds. No token values are printed, but the output is unstructured stdout. | Low (no secrets in these messages today; regression risk if a future call site passes sensitive data). | Gate behind `#if DEBUG`, or migrate to `os.Logger` with `.public`/`.private` privacy annotations. |
| Release transport assertion compiled out | The https/wss enforcement in `assertProductionTransportSecurity()` is DEBUG-only; a misconfigured Release build would rely on ATS alone. | Low (defaults are https/wss; ATS blocks arbitrary plaintext loads). | Add a runtime hard-fail or fallback-to-default in Release when `isATSSafe == false`. |
| No jailbreak / tamper detection | The app performs no jailbreak detection, debugger detection, or integrity checks. | Accepted for now; primarily relevant to Keychain/session theft on compromised devices. | Evaluate App Attest / DeviceCheck if threat model changes. |
| No certificate pinning | TLS relies on the system trust store; no pinning of the backend certificate. | Accepted for now; a device with a user-installed root CA could be MITM'd with user cooperation. | Pin via `URLSessionDelegate` challenge handling if warranted; weigh against certificate-rotation operational cost (the backend uses a DuckDNS domain with rotating certificates). |
| Print-based legacy logging | Outside the new realtime pipeline (which uses `os.Logger` via `RealtimeLog`), logging is print-based; hygiene depends on call-site discipline plus `masked`/`sanitizedMetadata`. | Low. | Migrate the rest of `AppLogger` to `os.Logger` (documented follow-up work). |
