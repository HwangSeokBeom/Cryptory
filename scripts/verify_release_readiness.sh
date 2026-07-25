#!/usr/bin/env bash

set -euo pipefail

project_path="Cryptory.xcodeproj"
scheme_name="Cryptory-Prod"
entitlements_path="Cryptory/Cryptory.entitlements"
release_config="Configurations/Release-Prod.xcconfig"

echo "== Cryptory iOS release readiness =="

for required_path in "$project_path" "$entitlements_path" "$release_config" "Cryptory/GoogleService-Info.plist"; do
  if [[ ! -e "$required_path" ]]; then
    echo "MISSING_FILE: $required_path" >&2
    exit 1
  fi
done

bundle_identifier="$(
  xcodebuild -project "$project_path" -scheme "$scheme_name" -configuration Release -showBuildSettings 2>/dev/null \
    | awk -F ' = ' '/^[[:space:]]*PRODUCT_BUNDLE_IDENTIFIER = / { print $2; exit }'
)"
development_team="$(
  xcodebuild -project "$project_path" -scheme "$scheme_name" -configuration Release -showBuildSettings 2>/dev/null \
    | awk -F ' = ' '/^[[:space:]]*DEVELOPMENT_TEAM = / { print $2; exit }'
)"
aps_environment="$(
  xcodebuild -project "$project_path" -scheme "$scheme_name" -configuration Release -showBuildSettings 2>/dev/null \
    | awk -F ' = ' '/^[[:space:]]*APS_ENVIRONMENT = / { print $2; exit }'
)"

[[ "$bundle_identifier" == "com.hwb.Cryptory" ]] || {
  echo "BUNDLE_ID_MISMATCH" >&2
  exit 1
}
[[ "$development_team" == "63SB2B8YJ5" ]] || {
  echo "TEAM_ID_MISMATCH" >&2
  exit 1
}
[[ "$aps_environment" == "production" ]] || {
  echo "APS_ENVIRONMENT_MISMATCH" >&2
  exit 1
}

/usr/libexec/PlistBuddy -c 'Print :aps-environment' "$entitlements_path" \
  | grep -Fx '$(APS_ENVIRONMENT)' >/dev/null

grep -F 'API_BASE_URL = https:/$()/crytory.duckdns.org' "$release_config" >/dev/null
grep -F 'WS_BASE_URL = wss:/$()/crytory.duckdns.org' "$release_config" >/dev/null

echo "PASS: Bundle ID, Team ID, production APS environment, HTTPS, and WSS contracts"
echo "NOTE: signing certificate, provisioning profile, APNs delivery, archive export, and upload were not verified"
