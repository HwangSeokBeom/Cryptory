#!/usr/bin/env bash
#
# ci_test.sh
#
# Runs the unit-test suite (and optionally a focused test subset) on a
# dynamically selected iOS simulator, unsigned, with a task-specific
# DerivedData path. Preserves the .xcresult bundle for upload on failure.
#
# Usage:
#   scripts/ci_test.sh                       # full CryptoryTests suite
#   scripts/ci_test.sh CryptoryTests/MarketStreamEngineTests
#                                            # focused subset via -only-testing
# Environment:
#   DERIVED_DATA_PATH  override the DerivedData location
#   RESULT_BUNDLE_PATH override the .xcresult output path
#   SCHEME             default Cryptory-Dev

set -euo pipefail

section() { printf '\n=== %s ===\n' "$1"; }

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "ERROR: must run inside a git repository" >&2
  exit 2
}
cd "$REPO_ROOT"

PROJECT="Cryptory.xcodeproj"
SCHEME="${SCHEME:-Cryptory-Dev}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-${TMPDIR:-/tmp}/cryptory-ci-derived-data}"
RESULT_BUNDLE_PATH="${RESULT_BUNDLE_PATH:-${TMPDIR:-/tmp}/cryptory-ci-results/tests-$(date +%Y%m%d-%H%M%S).xcresult}"
ONLY_TESTING="${1:-}"

[[ -d "$PROJECT" ]] || { echo "ERROR: $PROJECT not found in $REPO_ROOT" >&2; exit 2; }
mkdir -p "$(dirname "$RESULT_BUNDLE_PATH")"

# xcodebuild refuses to overwrite an existing result bundle; suffix if needed.
if [[ -e "$RESULT_BUNDLE_PATH" ]]; then
  N=1
  while [[ -e "${RESULT_BUNDLE_PATH%.xcresult}-${N}.xcresult" ]]; do N=$((N + 1)); done
  RESULT_BUNDLE_PATH="${RESULT_BUNDLE_PATH%.xcresult}-${N}.xcresult"
fi

section "Simulator selection"
# Ask xcodebuild itself which simulator destinations the scheme can use;
# simctl device sets do not always match xcodebuild's destination set.
source "${REPO_ROOT}/scripts/ci_destination.sh"
select_simulator_destination "$PROJECT" "$SCHEME"
echo "Selected simulator: ${DEST_NAME} (id=${DEST_ID})"

EXTRA_ARGS=()
if [[ -n "$ONLY_TESTING" ]]; then
  EXTRA_ARGS+=(-only-testing:"$ONLY_TESTING")
  section "Focused tests: $ONLY_TESTING"
else
  # Skip UI tests by default: simulator UI-test infrastructure is unreliable
  # on shared CI runners; run them explicitly when needed.
  EXTRA_ARGS+=(-skip-testing:CryptoryUITests)
  section "Unit tests (CryptoryTests; UI tests skipped by default)"
fi

set +e
xcodebuild test \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination "id=${DEST_ID}" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -resultBundlePath "$RESULT_BUNDLE_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  "${EXTRA_ARGS[@]}"
TEST_EXIT=$?
set -e

section "Result"
echo "xcresult bundle: ${RESULT_BUNDLE_PATH}"
if [[ "$TEST_EXIT" -ne 0 ]]; then
  echo "FAILED: tests exited with code ${TEST_EXIT}. Inspect the xcresult bundle above." >&2
  exit "$TEST_EXIT"
fi
echo "PASSED: test run completed successfully."
