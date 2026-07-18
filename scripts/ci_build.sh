#!/usr/bin/env bash
#
# ci_build.sh
#
# Unsigned simulator build for CI and local verification.
# - Resolves Swift packages, lists schemes, selects an available simulator
#   dynamically (never assumes a specific iPhone model), builds without
#   code signing.
# - Uses a task-specific DerivedData path; never touches the developer's
#   default DerivedData.
#
# Usage:
#   scripts/ci_build.sh [scheme]        # default scheme: Cryptory-Dev
# Environment:
#   DERIVED_DATA_PATH  override the DerivedData location
#   CONFIGURATION      Debug (default) or Release

set -euo pipefail

section() { printf '\n=== %s ===\n' "$1"; }

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "ERROR: must run inside a git repository" >&2
  exit 2
}
cd "$REPO_ROOT"

PROJECT="Cryptory.xcodeproj"
SCHEME="${1:-Cryptory-Dev}"
CONFIGURATION="${CONFIGURATION:-Debug}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-${TMPDIR:-/tmp}/cryptory-ci-derived-data}"

[[ -d "$PROJECT" ]] || { echo "ERROR: $PROJECT not found in $REPO_ROOT" >&2; exit 2; }

section "Toolchain"
xcodebuild -version

section "Schemes"
xcodebuild -list -project "$PROJECT"

section "Simulator selection"
# Pick the first available iPhone simulator; fall back to any available device.
DEST_ID="$(xcrun simctl list devices available --json | /usr/bin/python3 -c '
import json, sys
data = json.load(sys.stdin)
devices = [d for devs in data["devices"].values() for d in devs if d.get("isAvailable")]
iphones = [d for d in devices if d["name"].startswith("iPhone")]
pick = (iphones or devices)
if not pick:
    sys.exit(1)
print(pick[0]["udid"])
')" || { echo "ERROR: no available simulator found" >&2; exit 2; }
DEST_NAME="$(xcrun simctl list devices | grep "$DEST_ID" | sed 's/ (.*//' | head -1 | xargs)"
echo "Selected simulator: ${DEST_NAME} (${DEST_ID})"

section "Package resolution"
xcodebuild -resolvePackageDependencies -project "$PROJECT" -scheme "$SCHEME"

section "Build (${SCHEME}, ${CONFIGURATION}, unsigned)"
mkdir -p "$DERIVED_DATA_PATH"
xcodebuild build \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "id=${DEST_ID}" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  | tee "${DERIVED_DATA_PATH}/build.log"

section "Result"
echo "Build succeeded for scheme ${SCHEME} on ${DEST_NAME}."
echo "DerivedData: ${DERIVED_DATA_PATH}"
