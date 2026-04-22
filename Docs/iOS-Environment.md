# iOS Production / Dev Environment

## 1. Current Structure Summary

- `main` is the Production baseline branch and should normally run `Cryptory-Prod`.
- `dev` is the Development baseline branch and should normally run `Cryptory-Dev`.
- Branches do not select servers directly. Runtime server selection comes from the active Xcode scheme, build configuration, xcconfig values, and Info.plist injection.
- The app already had a central network configuration in `AppRuntimeConfiguration` / `APIConfiguration`, and WebSocket code already consumed runtime configuration. This was reused instead of replacing the network layer.
- The project has these targets: `Cryptory`, `CryptoryTests`, `CryptoryUITests`. No widget, extension, push notification entitlement, or associated domains entitlement was found.

## 2. Problems Found

- The previous shared scheme was a single `Cryptory` scheme, so app execution did not clearly communicate Prod vs Dev intent.
- URL values were partly hardcoded or defaulted from compile configuration, and external web links were not tied to the same runtime configuration.
- Local HTTP / ATS exceptions existed in a way that could affect production if left as one shared plist concern.
- Google Sign-In client ID and reversed client ID were hardcoded in code/plist instead of being injected with the rest of the runtime configuration.

## 3. Applied Strategy

- Keep the existing network and WebSocket layers.
- Add two shared schemes: `Cryptory-Prod` and `Cryptory-Dev`.
- Use existing build configurations conservatively:
  - `Debug` + `Debug-Dev.xcconfig` = Dev local server
  - `Release` + `Release-Prod.xcconfig` = Production server
- Inject runtime values through xcconfig-expanded Info.plist keys, then resolve them centrally in `AppRuntimeConfiguration.live`.
- Split only the app Info.plist where ATS differs:
  - Dev uses `Cryptory/Info-Dev.plist`
  - Prod uses `Cryptory/Info.plist`

## 4. Modified Files

- `Configurations/Debug-Dev.xcconfig`: Dev app name and local REST/WS/Web URL values.
- `Configurations/Release-Prod.xcconfig`: Production app name and REST/WS/Web URL values.
- `Cryptory.xcodeproj/project.pbxproj`: xcconfig references, Debug Dev plist, scheme/project wiring.
- `Cryptory.xcodeproj/xcshareddata/xcschemes/Cryptory-Dev.xcscheme`: shared Dev scheme.
- `Cryptory.xcodeproj/xcshareddata/xcschemes/Cryptory-Prod.xcscheme`: shared Prod scheme.
- `Cryptory.xcodeproj/xcshareddata/xcschemes/Cryptory.xcscheme`: removed old ambiguous shared scheme.
- `Cryptory/Info.plist`: Production plist with production-only ATS exception.
- `Cryptory/Info-Dev.plist`: Dev plist with local networking ATS handling.
- `Cryptory/Services/NetworkService.swift`: centralized Dev/Prod runtime resolution.
- `Cryptory/Services/AppExternalLink.swift`: external web links now use `WEB_BASE_URL`.
- `Cryptory/Services/GoogleSignInProvider.swift`: client ID now reads from Info.plist with legacy fallback.
- `Cryptory/Services/AppLogger.swift`: configuration log channel.
- `Cryptory/CryptoryApp.swift`: loads runtime configuration at launch so environment logs print immediately.
- `CryptoryTests/NetworkAndAuthTests.swift`: Dev/Prod/default/override coverage.
- `CryptoryTests/FormAndViewStateTests.swift`: external link expectation follows configured web base URL.

## 5. Scheme Mapping

| Scheme | Build action | Run | Test | Profile | Analyze | Archive |
| --- | --- | --- | --- | --- | --- | --- |
| `Cryptory-Dev` | `Debug` | `Debug` | `Debug` | `Debug` | `Debug` | `Debug` |
| `Cryptory-Prod` | `Release` | `Release` | `Debug` | `Release` | `Release` | `Release` |

`Cryptory-Prod` tests use `Debug` so the existing `@testable import Cryptory` test flow remains buildable. Running, profiling, analyzing, and archiving the Prod app use `Release`.

## 6. Final URL Table

| Value | Production (`Cryptory-Prod`) | Dev local (`Cryptory-Dev`) |
| --- | --- | --- |
| `APP_ENV` | `Prod` | `Dev` |
| App name | `Cryptory` | `Cryptory Dev` |
| `API_BASE_URL` | `http://crytory.duckdns.org` | `http://127.0.0.1:3002` |
| `WS_BASE_URL` | `ws://crytory.duckdns.org` | `ws://127.0.0.1:3002` |
| `WEB_BASE_URL` | `http://crytory.duckdns.org` | `http://127.0.0.1:3002` |
| Public WS URL | `ws://crytory.duckdns.org/ws/market` | `ws://127.0.0.1:3002/ws/market` |
| Private WS URL | `ws://crytory.duckdns.org/ws/trading` | `ws://127.0.0.1:3002/ws/trading` |

## 7. Simulator Local Server

1. Start the backend locally on port `3002`.
2. Run `Cryptory-Dev` in Xcode.
3. The simulator connects to `http://127.0.0.1:3002` and `ws://127.0.0.1:3002`.
4. To use a different port, update `LOCAL_SERVER_PORT` in `Configurations/Debug-Dev.xcconfig` and rebuild.

## 8. Real Device Local Server

1. Start the backend bound to the Mac's LAN interface, usually `0.0.0.0:3002`.
2. Put the iPhone and Mac on the same local network.
3. Find the Mac LAN IP, for example `192.168.x.x`.
4. Change `LOCAL_SERVER_HOST` in `Configurations/Debug-Dev.xcconfig` from `127.0.0.1` to that LAN IP and rebuild `Cryptory-Dev`.
5. Keep port `3002` or update `LOCAL_SERVER_PORT` consistently.
6. Allow the iOS local network permission prompt if shown.

## 9. New Developer Runbook

1. Clone the repository and open `Cryptory.xcodeproj`.
2. For production behavior, choose `Cryptory-Prod` and run.
3. For local development, start the local backend and choose `Cryptory-Dev`.
4. If the local backend is not on `127.0.0.1:3002`, edit `Configurations/Debug-Dev.xcconfig`.
5. Verify startup logs:
   - `[CONFIG] Environment -> Dev` or `[CONFIG] Environment -> Prod`
   - `[CONFIG] REST base URL -> ...`
   - `[CONFIG] Public WS URL -> ...`

## 10. Login, Deep Link, Push, and Web Auth Check

- Google Sign-In URL scheme remains the existing reversed client ID, but is now injected through build settings.
- Google client ID is read from Info.plist with a fallback to the previous hardcoded value.
- Apple Sign-In entitlement remains unchanged.
- No associated domains entitlement was found.
- No push notification entitlement was found.
- No separate widget or extension target was found.
- If the local backend needs a different OAuth redirect or callback allowlist, update the backend/provider configuration separately; the app-side callback scheme has not been changed.

## 11. Notes and Cautions

- Production still uses HTTP because the requested production base URL is HTTP. Production ATS is limited to `crytory.duckdns.org`.
- Dev local networking is limited to Dev plist handling: `NSAllowsLocalNetworking`, `localhost`, `127.0.0.1`, and local network usage description.
- `WEB_BASE_URL` now follows the selected environment. If production legal/policy pages are not served from `http://crytory.duckdns.org`, provide environment-specific web/legal URLs in xcconfig.
- Do not reintroduce URL literals in feature code. Add values to `AppRuntimeConfiguration` and xcconfig instead.

## 12. Remaining TODO

- Confirm the local backend port is permanently `3002`; otherwise update `LOCAL_SERVER_PORT`.
- Confirm production web/legal paths are served under `WEB_BASE_URL`.
- Confirm Google/OAuth provider redirect allowlists if backend callback behavior differs between production and local development.
- Add a distinct Dev bundle identifier only if simultaneous Prod and Dev installs become a requirement.
