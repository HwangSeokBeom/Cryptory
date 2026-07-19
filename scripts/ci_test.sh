#!/usr/bin/env bash
#
# ci_test.sh
#
# Unit-test pipeline with observable phase boundaries. The previous
# single-command `xcodebuild test` flow hung on a GitHub-hosted runner
# AFTER building the test bundles and BEFORE XCTest reported any test
# (41 minutes of silence, job cancelled manually). This script splits the
# flow so every boundary reports independently and a hang is bounded,
# diagnosed, and preserved as artifacts instead of eating the job timeout.
#
# Phases (subcommands):
#   build        xcodebuild build-for-testing (unit-only scheme), then prove
#                the UI-test runner was NOT built
#   boot         explicitly boot the selected simulator and wait for
#                `simctl bootstatus`; never rely on xcodebuild implicit boot
#   smoke        test-without-building a single deterministic parser class
#                (WebSocketParserTests) — isolates test-host/simulator
#                infrastructure failures from suite-level failures
#   test [SPEC]  test-without-building the full CryptoryTests suite, or a
#                focused subset when SPEC (e.g. CryptoryTests/Foo) is given
#
# No subcommand: run build, boot, smoke, test in order (local flow).
# A first argument containing '/' is shorthand for `test <SPEC>`.
#
# The default scheme is Cryptory-UnitTests, whose build and test actions
# contain only Cryptory.app (TEST_HOST) and CryptoryTests. Do NOT use
# Cryptory-Dev here: its test action includes CryptoryUITests, and
# -skip-testing does not stop the UI-test runner from being built.
#
# Environment:
#   DERIVED_DATA_PATH      DerivedData location (shared across phases)
#   RESULT_BUNDLE_PATH     base .xcresult path; phases derive labeled bundles
#   SCHEME                 default Cryptory-UnitTests
#   DEST_ID                override simulator UUID (skips selection)
#   BUILD_TIMEOUT_SECONDS  watchdog for build-for-testing (default 1800)
#   BOOT_TIMEOUT_SECONDS   watchdog for simulator boot     (default 600)
#   SMOKE_TIMEOUT_SECONDS  watchdog for the smoke class    (default 600)
#   TEST_TIMEOUT_SECONDS   watchdog for suite execution    (default 900)

set -euo pipefail

section() { printf '\n=== %s ===\n' "$1"; }

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "ERROR: must run inside a git repository" >&2
  exit 2
}
cd "$REPO_ROOT"

source "${REPO_ROOT}/scripts/ci_destination.sh"
source "${REPO_ROOT}/scripts/ci_test_lib.sh"

PROJECT="Cryptory.xcodeproj"
SCHEME="${SCHEME:-Cryptory-UnitTests}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-${TMPDIR:-/tmp}/cryptory-ci-derived-data}"
RESULT_BUNDLE_PATH="${RESULT_BUNDLE_PATH:-${TMPDIR:-/tmp}/cryptory-ci-results/tests.xcresult}"
RESULT_DIR="$(dirname "$RESULT_BUNDLE_PATH")"
LOG_DIR="${RESULT_DIR}/logs"
DIAG_DIR="${RESULT_DIR}/diagnostics"
DEST_CACHE="${DERIVED_DATA_PATH}/ci-destination.env"
SMOKE_CLASS="CryptoryTests/WebSocketParserTests"

BUILD_TIMEOUT_SECONDS="${BUILD_TIMEOUT_SECONDS:-1800}"
BOOT_TIMEOUT_SECONDS="${BOOT_TIMEOUT_SECONDS:-600}"
SMOKE_TIMEOUT_SECONDS="${SMOKE_TIMEOUT_SECONDS:-600}"
TEST_TIMEOUT_SECONDS="${TEST_TIMEOUT_SECONDS:-900}"

[[ -d "$PROJECT" ]] || { echo "ERROR: $PROJECT not found in $REPO_ROOT" >&2; exit 2; }
mkdir -p "$LOG_DIR" "$DIAG_DIR" "$DERIVED_DATA_PATH"

# labeled_result_bundle <label> — derive a unique per-phase xcresult path
# (xcodebuild refuses to overwrite an existing bundle).
labeled_result_bundle() {
  local label="$1" base path n
  base="${RESULT_BUNDLE_PATH%.xcresult}-${label}.xcresult"
  path="$base"
  n=1
  while [[ -e "$path" ]]; do path="${base%.xcresult}-${n}.xcresult"; n=$((n + 1)); done
  printf '%s\n' "$path"
}

# resolve_destination — sets DEST_ID / DEST_NAME. Selection runs once and is
# cached in DerivedData so every phase (separate CI steps) uses the SAME
# simulator UUID. A DEST_ID provided via env wins.
resolve_destination() {
  if [[ -n "${DEST_ID:-}" ]]; then
    DEST_NAME="${DEST_NAME:-env-provided}"
    echo "Using simulator from environment: ${DEST_NAME} (id=${DEST_ID})"
    return
  fi
  if [[ -f "$DEST_CACHE" ]]; then
    # shellcheck disable=SC1090
    source "$DEST_CACHE"
    if xcrun simctl list devices 2>/dev/null | grep -q "$DEST_ID"; then
      echo "Using cached simulator: ${DEST_NAME} (id=${DEST_ID})"
      return
    fi
    echo "Cached simulator ${DEST_ID} no longer exists; reselecting."
  fi
  select_simulator_destination "$PROJECT" "$SCHEME"
  printf 'DEST_ID=%q\nDEST_NAME=%q\n' "$DEST_ID" "$DEST_NAME" > "$DEST_CACHE"
  echo "Selected simulator: ${DEST_NAME} (id=${DEST_ID})"
}

# device_state — prints the simctl state (Booted/Shutdown/...) for DEST_ID.
device_state() {
  xcrun simctl list devices 2>/dev/null \
    | grep "$DEST_ID" | sed -En 's/.*\((Booted|Shutdown|Shutting Down|Creating)\).*/\1/p' | head -1
}

print_device_record() {
  echo "Device record for ${DEST_ID}:"
  xcrun simctl list -j devices 2>/dev/null | grep -B0 -A12 "\"udid\" : \"${DEST_ID}\"" || true
  xcrun simctl list devices 2>/dev/null | grep "$DEST_ID" || true
}

cmd_build() {
  section "Phase: build-for-testing (${SCHEME})"
  resolve_destination
  local log="${LOG_DIR}/build-for-testing.log"
  local rc=0
  run_with_watchdog "$BUILD_TIMEOUT_SECONDS" "build-for-testing" "$log" "$DIAG_DIR" -- \
    xcodebuild build-for-testing \
      -project "$PROJECT" \
      -scheme "$SCHEME" \
      -destination "id=${DEST_ID}" \
      -derivedDataPath "$DERIVED_DATA_PATH" \
      CODE_SIGNING_ALLOWED=NO \
      CODE_SIGNING_REQUIRED=NO \
      CODE_SIGN_IDENTITY="" \
    || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    echo "BOUNDARY: test bundle construction completed: NO (exit ${rc})" >&2
    return "$rc"
  fi
  echo "BOUNDARY: test bundle construction completed: yes"
  section "Prove UI-test runner was not built"
  assert_no_ui_runner "$DERIVED_DATA_PATH" "$log"
}

cmd_boot() {
  section "Phase: explicit simulator boot"
  resolve_destination
  local state
  state="$(device_state || true)"
  echo "Pre-boot state: ${state:-unknown}"
  if [[ "$state" != "Shutdown" && "$state" != "Booted" ]]; then
    echo "Shutting down ${DEST_ID} to leave a clean state first."
    xcrun simctl shutdown "$DEST_ID" 2>/dev/null || true
  fi
  local log="${LOG_DIR}/simulator-boot.log"
  local rc=0
  run_with_watchdog "$BOOT_TIMEOUT_SECONDS" "simulator-boot" "$log" "$DIAG_DIR" -- \
    xcrun simctl bootstatus "$DEST_ID" -b || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    echo "BOUNDARY: simulator boot completed: NO (exit ${rc})" >&2
    print_device_record >&2
    return "$rc"
  fi
  section "Simulator state after boot"
  print_device_record
  state="$(device_state || true)"
  if [[ "$state" != "Booted" ]]; then
    echo "ERROR: expected Booted, got '${state:-unknown}'" >&2
    return 1
  fi
  echo "BOUNDARY: simulator boot completed: yes (${DEST_NAME}, id=${DEST_ID})"
}

# run_tests <label> <timeout> <only-spec>
run_tests() {
  local label="$1" timeout="$2" only_spec="$3"
  resolve_destination
  local bundle log rc=0
  bundle="$(labeled_result_bundle "$label")"
  log="${LOG_DIR}/${label}.log"
  echo "Simulator: ${DEST_NAME} (id=${DEST_ID}, state=$(device_state || echo unknown))"
  echo "Result bundle: ${bundle}"
  # Point the diagnostics collector at this phase's bundle.
  local saved_result_bundle="$RESULT_BUNDLE_PATH"
  RESULT_BUNDLE_PATH="$bundle"
  run_with_watchdog "$timeout" "$label" "$log" "$DIAG_DIR" -- \
    xcodebuild test-without-building \
      -project "$PROJECT" \
      -scheme "$SCHEME" \
      -destination "id=${DEST_ID}" \
      -derivedDataPath "$DERIVED_DATA_PATH" \
      -resultBundlePath "$bundle" \
      -only-testing:"$only_spec" \
    || rc=$?
  RESULT_BUNDLE_PATH="$saved_result_bundle"

  section "Boundary report (${label})"
  report_test_boundaries "$log"
  if ! test_log_execution_began "$log"; then
    echo "DIAGNOSIS: XCTest never started executing '${only_spec}'." >&2
    echo "  -> failure is in test-host launch / simulator / testmanagerd" >&2
    echo "     infrastructure or test-bundle load (static initializers)," >&2
    echo "     NOT in an individual test method." >&2
  elif ! test_log_execution_completed "$log"; then
    echo "DIAGNOSIS: execution began but never reached a verdict. Last started:" >&2
    grep -E "Test [Cc]ase '.+' started" "$log" | tail -3 >&2 || true
  fi
  if [[ "$rc" -ne 0 ]]; then
    echo "FAILED: ${label} exited with code ${rc}. xcresult: ${bundle}" >&2
    return "$rc"
  fi
  echo "PASSED: ${label} completed successfully. xcresult: ${bundle}"
}

cmd_smoke() {
  section "Phase: smoke probe (${SMOKE_CLASS}, test-without-building)"
  # One small deterministic parser class that never touches the realtime
  # engine. If THIS cannot start, the problem is infrastructure, not tests.
  run_tests "smoke" "$SMOKE_TIMEOUT_SECONDS" "$SMOKE_CLASS"
}

cmd_test() {
  local spec="${1:-CryptoryTests}"
  local label
  if [[ "$spec" == "CryptoryTests" ]]; then
    label="unit-full"
    section "Phase: full unit suite (${spec}, test-without-building)"
  else
    label="focused-$(printf '%s' "${spec##*/}" | tr -cd 'A-Za-z0-9_-')"
    section "Phase: focused tests (${spec}, test-without-building)"
  fi
  run_tests "$label" "$TEST_TIMEOUT_SECONDS" "$spec"
}

MODE="${1:-all}"
case "$MODE" in
  build) cmd_build ;;
  boot)  cmd_boot ;;
  smoke) cmd_smoke ;;
  test)  shift; cmd_test "${1:-CryptoryTests}" ;;
  */*)   cmd_test "$MODE" ;;  # back-compat: ci_test.sh CryptoryTests/SomeClass
  all)
    cmd_build
    cmd_boot
    cmd_smoke
    cmd_test "CryptoryTests"
    ;;
  *)
    echo "Usage: scripts/ci_test.sh [build|boot|smoke|test [Suite/Class]]" >&2
    exit 2
    ;;
esac
