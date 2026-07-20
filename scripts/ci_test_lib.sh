#!/usr/bin/env bash
#
# ci_test_lib.sh
#
# Shared helpers for scripts/ci_test.sh. Source this file; it defines
# functions only and is safe under `set -euo pipefail`.
#
# Covered concerns:
#   - detecting whether XCTest execution actually began / completed in an
#     xcodebuild log (the CI hang this repo saw produced a log that ended
#     after linking, before any `Test Suite ... started` line)
#   - proving the unit-test path never builds the UI-test runner
#   - a bounded watchdog around long xcodebuild invocations that collects
#     diagnostics BEFORE terminating the hung process, then exits nonzero
#
# Tunables (env):
#   WATCHDOG_POLL_SECONDS       poll interval (default 5)
#   WATCHDOG_HEARTBEAT_SECONDS  liveness heartbeat interval (default 60)
#   WATCHDOG_GRACE_SECONDS      TERM->KILL grace period (default 10)

# --- log analysis -----------------------------------------------------------

# test_log_execution_began <log>
# Returns 0 iff the log shows XCTest actually started executing tests.
test_log_execution_began() {
  grep -Eq "Test Suite '.+' started|Test Case '.+' started|Test case '.+' (started|passed|failed)|Testing started" "$1"
}

# test_log_execution_completed <log>
# Returns 0 iff the log shows xcodebuild reached a terminal test verdict.
test_log_execution_completed() {
  grep -Eq "\*\* TEST EXECUTE SUCCEEDED \*\*|\*\* TEST EXECUTE FAILED \*\*|\*\* TEST SUCCEEDED \*\*|\*\* TEST FAILED \*\*" "$1"
}

# report_test_boundaries <log>
# Prints an explicit, machine-greppable summary of the three boundaries the
# hang investigation cares about. Purely informational; never fails.
report_test_boundaries() {
  local log="$1"
  if test_log_execution_began "$log"; then
    echo "BOUNDARY: test execution began: yes"
  else
    echo "BOUNDARY: test execution began: NO (log never reached 'Test Suite ... started')"
  fi
  if test_log_execution_completed "$log"; then
    echo "BOUNDARY: test execution completed: yes"
  else
    echo "BOUNDARY: test execution completed: NO"
  fi
}

# assert_no_ui_runner <derived_data> <log>
# Fails (returns 1) if the UI-test runner or UI-test bundle was produced or
# mentioned as a build product. `-skip-testing:CryptoryUITests` does NOT
# prevent the UI target from being BUILT when the scheme's test action
# includes it — this assertion is the proof the unit-only scheme works.
assert_no_ui_runner() {
  local derived_data="$1" log="$2" products bad=""
  products="${derived_data}/Build/Products"
  if [[ -d "$products" ]]; then
    if find "$products" \( -name 'CryptoryUITests-Runner.app' -o -name 'CryptoryUITests.xctest' \) 2>/dev/null | grep -q .; then
      bad="UI-test products found under ${products}"
    fi
  fi
  if [[ -z "$bad" && -f "$log" ]] \
    && grep -Eq 'CryptoryUITests-Runner\.app|CryptoryUITests\.xctest|Target CryptoryUITests|target CryptoryUITests' "$log"; then
    bad="build log references CryptoryUITests build products: $log"
  fi
  if [[ -n "$bad" ]]; then
    echo "ERROR: unit-test path built the UI-test runner: ${bad}" >&2
    return 1
  fi
  echo "VERIFIED: no CryptoryUITests-Runner.app / CryptoryUITests.xctest built on the unit-test path."
}

# --- diagnostics ------------------------------------------------------------

# collect_hang_diagnostics <label> <log> <diag_dir>
# Snapshots process / simulator / DerivedData state into <diag_dir>.
# Reads (optional) globals: DEST_ID, DERIVED_DATA_PATH, RESULT_BUNDLE_PATH,
# WATCHDOG_COMMAND. Never fails; diagnostics must not mask the timeout.
collect_hang_diagnostics() {
  local label="$1" log="$2" diag_dir="$3"
  mkdir -p "$diag_dir"
  {
    echo "label: ${label}"
    echo "utc: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo "command: ${WATCHDOG_COMMAND:-unknown}"
    echo "scheme: ${SCHEME:-unknown}"
    echo "destination id: ${DEST_ID:-unknown}"
    echo "derived data: ${DERIVED_DATA_PATH:-unknown}"
    echo "result bundle: ${RESULT_BUNDLE_PATH:-unknown}"
  } > "${diag_dir}/${label}-timeout-marker.txt" 2>&1 || true

  ps aux 2>/dev/null | grep -E 'xcodebuild|testmanagerd|CoreSimulator|Simulator|Cryptory' | grep -v grep \
    > "${diag_dir}/${label}-processes.txt" 2>&1 || true

  xcrun simctl list devices > "${diag_dir}/${label}-simctl-devices.txt" 2>&1 || true

  if [[ -n "${DEST_ID:-}" ]]; then
    # Plain `simctl bootstatus` can itself block on an unbootable device, so
    # snapshot the JSON device record instead of monitoring boot progress.
    xcrun simctl list -j devices 2>/dev/null \
      | grep -B2 -A8 "${DEST_ID}" > "${diag_dir}/${label}-device-record.txt" 2>&1 || true
  fi

  local coresim_log="${HOME}/Library/Logs/CoreSimulator/CoreSimulator.log"
  if [[ -f "$coresim_log" ]]; then
    tail -n 300 "$coresim_log" > "${diag_dir}/${label}-coresimulator-log-tail.txt" 2>&1 || true
  fi

  if [[ -n "${RESULT_BUNDLE_PATH:-}" && -e "${RESULT_BUNDLE_PATH}" ]]; then
    ls -R "${RESULT_BUNDLE_PATH}" > "${diag_dir}/${label}-xcresult-contents.txt" 2>&1 || true
  fi

  if [[ -n "${DERIVED_DATA_PATH:-}" && -d "${DERIVED_DATA_PATH}/Logs/Test" ]]; then
    ls -la "${DERIVED_DATA_PATH}/Logs/Test" > "${diag_dir}/${label}-derived-data-test-logs.txt" 2>&1 || true
  fi

  if [[ -f "$log" ]]; then
    {
      report_test_boundaries "$log"
      echo "--- last 100 log lines ---"
      tail -n 100 "$log"
    } > "${diag_dir}/${label}-last-output.txt" 2>&1 || true
  fi

  echo "Diagnostics collected in ${diag_dir} (prefix ${label}-)."
}

# --- watchdog ---------------------------------------------------------------

# run_with_watchdog <timeout_seconds> <label> <log> <diag_dir> -- <cmd...>
# Runs <cmd> with output streamed to the console and captured in <log>.
# If it exceeds <timeout_seconds>: collects diagnostics FIRST, then TERM,
# then KILL, and returns 124. Otherwise returns the command's exit code.
# Emits a heartbeat so a hung phase is visible long before the timeout.
run_with_watchdog() {
  local timeout="$1" label="$2" log="$3" diag_dir="$4"
  shift 4
  [[ "$1" == "--" ]] && shift
  local poll="${WATCHDOG_POLL_SECONDS:-5}"
  local heartbeat="${WATCHDOG_HEARTBEAT_SECONDS:-60}"
  local grace="${WATCHDOG_GRACE_SECONDS:-10}"

  WATCHDOG_COMMAND="$*"
  : > "$log"
  "$@" > "$log" 2>&1 &
  local cmd_pid=$!
  tail -f "$log" &
  local tail_pid=$!

  local elapsed=0 since_heartbeat=0 rc=0
  while kill -0 "$cmd_pid" 2>/dev/null; do
    if (( elapsed >= timeout )); then
      echo ""
      echo "WATCHDOG: '${label}' exceeded ${timeout}s; collecting diagnostics before terminating." >&2
      collect_hang_diagnostics "$label" "$log" "$diag_dir" >&2 || true
      kill -TERM "$cmd_pid" 2>/dev/null || true
      local waited=0
      while kill -0 "$cmd_pid" 2>/dev/null && (( waited < grace )); do
        sleep 1; waited=$((waited + 1))
      done
      kill -KILL "$cmd_pid" 2>/dev/null || true
      wait "$cmd_pid" 2>/dev/null || true
      kill "$tail_pid" 2>/dev/null || true
      wait "$tail_pid" 2>/dev/null || true
      echo "WATCHDOG: '${label}' terminated after timeout." >&2
      return 124
    fi
    sleep "$poll"
    elapsed=$((elapsed + poll))
    since_heartbeat=$((since_heartbeat + poll))
    if (( since_heartbeat >= heartbeat )); then
      echo "[watchdog] ${label}: still running after ${elapsed}s (limit ${timeout}s)"
      since_heartbeat=0
    fi
  done

  set +e
  wait "$cmd_pid"
  rc=$?
  set -e
  # Let tail drain the final buffered lines before tearing it down.
  sleep 1
  kill "$tail_pid" 2>/dev/null || true
  wait "$tail_pid" 2>/dev/null || true
  return "$rc"
}
