#!/usr/bin/env bash
#
# test_ci_test_lib.sh
#
# Shell-level regression tests for scripts/ci_test_lib.sh. Hermetic: no
# xcodebuild or simulator is touched; logs are synthesized and the watchdog
# is exercised with plain shell commands.
#
# Usage: bash scripts/test_ci_test_lib.sh

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
source "${REPO_ROOT}/scripts/ci_test_lib.sh"

PASS=0
fail() { echo "FAIL: $1" >&2; exit 1; }
ok() { PASS=$((PASS + 1)); echo "ok: $1"; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/ci-test-lib-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# 1. A log that ends after linking (the observed CI hang) is reported as
#    "execution never began".
HANG_LOG="${WORK}/hang.log"
cat > "$HANG_LOG" <<'EOF'
Ld /path/DerivedData/Build/Products/Debug-iphonesimulator/CryptoryTests.xctest/CryptoryTests normal
RegisterExecutionPolicyException /path/CryptoryTests.xctest
** TEST BUILD SUCCEEDED **
EOF
if test_log_execution_began "$HANG_LOG"; then
  fail "post-link hang log must NOT count as execution began"
fi
if test_log_execution_completed "$HANG_LOG"; then
  fail "post-link hang log must NOT count as execution completed"
fi
BOUNDARIES="$(report_test_boundaries "$HANG_LOG")"
[[ "$BOUNDARIES" == *"test execution began: NO"* ]] \
  || fail "boundary report must state execution never began"
ok "post-link hang log: execution began=NO, completed=NO"

# 2. A normal successful run reports both boundaries.
GOOD_LOG="${WORK}/good.log"
cat > "$GOOD_LOG" <<'EOF'
Test Suite 'All tests' started at 2026-07-19 12:00:00.000
Test Suite 'CryptoryTests.xctest' started at 2026-07-19 12:00:00.001
Test Case '-[CryptoryTests.WebSocketParserTests testMarketWebSocketTickerParserMatchesContract]' started.
Test Case '-[CryptoryTests.WebSocketParserTests testMarketWebSocketTickerParserMatchesContract]' passed (0.001 seconds).
Test Suite 'All tests' passed at 2026-07-19 12:00:01.000.
** TEST EXECUTE SUCCEEDED **
EOF
test_log_execution_began "$GOOD_LOG" || fail "successful log must count as began"
test_log_execution_completed "$GOOD_LOG" || fail "successful log must count as completed"
ok "successful run log: execution began=yes, completed=yes"

# 3. Execution began but hung mid-suite: began=yes, completed=NO.
MID_LOG="${WORK}/mid.log"
cat > "$MID_LOG" <<'EOF'
Test Suite 'CryptoryTests.xctest' started at 2026-07-19 12:00:00.001
Test Case '-[CryptoryTests.ViewModelStateTests testFoo]' started.
EOF
test_log_execution_began "$MID_LOG" || fail "mid-suite log must count as began"
if test_log_execution_completed "$MID_LOG"; then
  fail "mid-suite log must NOT count as completed"
fi
ok "mid-suite hang log: execution began=yes, completed=NO"

# 4. assert_no_ui_runner fails when the UI-test runner exists in products.
DD_BAD="${WORK}/dd-bad"
mkdir -p "${DD_BAD}/Build/Products/Debug-iphonesimulator/CryptoryUITests-Runner.app"
: > "${WORK}/empty-build.log"
if assert_no_ui_runner "$DD_BAD" "${WORK}/empty-build.log" 2>/dev/null; then
  fail "CryptoryUITests-Runner.app in products must fail the assertion"
fi
ok "assert_no_ui_runner rejects a built UI-test runner"

# 5. assert_no_ui_runner fails when the build log references the UI bundle.
DD_CLEAN="${WORK}/dd-clean"
mkdir -p "${DD_CLEAN}/Build/Products/Debug-iphonesimulator/CryptoryTests.xctest"
BAD_LOG="${WORK}/bad-build.log"
echo "Ld /x/CryptoryUITests.xctest/CryptoryUITests normal" > "$BAD_LOG"
if assert_no_ui_runner "$DD_CLEAN" "$BAD_LOG" 2>/dev/null; then
  fail "build log referencing CryptoryUITests.xctest must fail the assertion"
fi
ok "assert_no_ui_runner rejects a log that built the UI bundle"

# 6. assert_no_ui_runner passes for a clean unit-only build.
CLEAN_LOG="${WORK}/clean-build.log"
cat > "$CLEAN_LOG" <<'EOF'
Ld /x/Build/Products/Debug-iphonesimulator/Cryptory.app/Cryptory normal
Ld /x/Build/Products/Debug-iphonesimulator/CryptoryTests.xctest/CryptoryTests normal
** TEST BUILD SUCCEEDED **
EOF
assert_no_ui_runner "$DD_CLEAN" "$CLEAN_LOG" > /dev/null \
  || fail "clean unit-only build must pass the assertion"
ok "assert_no_ui_runner passes a clean unit-only build"

# 7. Watchdog: a fast successful command returns its exit code (0).
LOG7="${WORK}/wd-ok.log"
DIAG7="${WORK}/diag-ok"
WATCHDOG_POLL_SECONDS=1 run_with_watchdog 30 "wd-ok" "$LOG7" "$DIAG7" -- \
  bash -c 'echo done' > /dev/null \
  || fail "watchdog must return 0 for a successful command"
grep -q done "$LOG7" || fail "watchdog must capture command output in the log"
ok "watchdog passes through success and captures output"

# 8. Watchdog: a failing command's exit code is preserved.
LOG8="${WORK}/wd-fail.log"
RC=0
WATCHDOG_POLL_SECONDS=1 run_with_watchdog 30 "wd-fail" "$LOG8" "$DIAG7" -- \
  bash -c 'exit 3' > /dev/null || RC=$?
[[ "$RC" -eq 3 ]] || fail "watchdog must preserve exit code 3, got ${RC}"
ok "watchdog preserves the command's nonzero exit code"

# 9. Watchdog: a hung command is terminated, diagnostics are written first,
#    and the return code is 124.
LOG9="${WORK}/wd-hang.log"
DIAG9="${WORK}/diag-hang"
RC=0
WATCHDOG_POLL_SECONDS=1 WATCHDOG_GRACE_SECONDS=1 \
  run_with_watchdog 2 "wd-hang" "$LOG9" "$DIAG9" -- \
  bash -c 'sleep 63217' > /dev/null 2>&1 || RC=$?
[[ "$RC" -eq 124 ]] || fail "watchdog must return 124 on timeout, got ${RC}"
[[ -f "${DIAG9}/wd-hang-timeout-marker.txt" ]] \
  || fail "watchdog must write a timeout marker before terminating"
[[ -f "${DIAG9}/wd-hang-processes.txt" ]] \
  || fail "watchdog must snapshot processes before terminating"
if pgrep -f 'sleep 63217' > /dev/null 2>&1; then
  fail "watchdog must actually terminate the hung command"
fi
ok "watchdog times out at the bound, collects diagnostics, returns 124"

echo ""
echo "PASSED: ${PASS} ci_test_lib checks"
