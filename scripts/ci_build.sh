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
# Ask xcodebuild itself which simulator destinations the scheme can use;
# simctl device sets do not always match xcodebuild's destination set.
source "${REPO_ROOT}/scripts/ci_destination.sh"
select_simulator_destination "$PROJECT" "$SCHEME"
echo "Selected simulator: ${DEST_NAME} (id=${DEST_ID})"

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
