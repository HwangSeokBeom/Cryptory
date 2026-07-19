#!/usr/bin/env bash
#
# test_ci_whitespace_check.sh
#
# Shell regression tests for ci_whitespace_check.sh:
#   1. A commit introducing trailing whitespace fails (exit 1) with
#      BEFORE_SHA set (push event path).
#   2. The same commit fails via the HEAD~1 fallback (zero/absent
#      BEFORE_SHA — push to a new branch).
#   3. A clean commit passes (exit 0).
#   4. A root commit is checked against the empty tree, not skipped.
#
# Usage: scripts/test_ci_whitespace_check.sh
# Exit codes: 0 = all cases pass, 1 = a case failed.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECKER="${SCRIPT_DIR}/ci_whitespace_check.sh"
[[ -f "$CHECKER" ]] || { echo "ERROR: checker not found at $CHECKER" >&2; exit 1; }

FAILED=0
fail() { echo "FAIL: $1" >&2; FAILED=1; }
pass() { echo "ok: $1"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

make_repo() {
  local dir="$1"
  git -C "$dir" init -q
  git -C "$dir" config user.email test@example.invalid
  git -C "$dir" config user.name "whitespace test"
}

run_checker() {
  # $1 = repo dir; remaining args = env VAR=VALUE pairs.
  local dir="$1"; shift
  (cd "$dir" && env "$@" bash "$CHECKER")
}

# --- Repo with a clean first commit and a whitespace-error second commit.
REPO="$TMP/repo"
mkdir -p "$REPO"
make_repo "$REPO"
echo "clean line" > "$REPO/file.txt"
git -C "$REPO" add -A && git -C "$REPO" commit -qm "clean base"
FIRST_SHA="$(git -C "$REPO" rev-parse HEAD)"
printf 'trailing space \n' >> "$REPO/file.txt"
git -C "$REPO" add -A && git -C "$REPO" commit -qm "introduce trailing whitespace"

set +e
run_checker "$REPO" BEFORE_SHA="$FIRST_SHA" >/dev/null 2>&1
STATUS=$?
set -e
if [[ "$STATUS" -eq 1 ]]; then
  pass "whitespace error fails with BEFORE_SHA (push path)"
else
  fail "expected exit 1 with BEFORE_SHA, got ${STATUS}"
fi

set +e
run_checker "$REPO" BEFORE_SHA="0000000000000000000000000000000000000000" >/dev/null 2>&1
STATUS=$?
set -e
if [[ "$STATUS" -eq 1 ]]; then
  pass "zero BEFORE_SHA falls back to HEAD~1 and still fails"
else
  fail "expected exit 1 via HEAD~1 fallback, got ${STATUS}"
fi

# --- Clean follow-up commit passes.
printf 'clean addition\n' > "$REPO/clean.txt"
git -C "$REPO" add clean.txt && git -C "$REPO" commit -qm "clean addition"
set +e
run_checker "$REPO" BEFORE_SHA="$(git -C "$REPO" rev-parse HEAD~1)" >/dev/null 2>&1
STATUS=$?
set -e
if [[ "$STATUS" -eq 0 ]]; then
  pass "clean commit passes"
else
  fail "expected exit 0 for a clean commit, got ${STATUS}"
fi

# --- Root commit with whitespace error is checked against the empty tree.
ROOT_REPO="$TMP/root"
mkdir -p "$ROOT_REPO"
make_repo "$ROOT_REPO"
printf 'bad root \n' > "$ROOT_REPO/root.txt"
git -C "$ROOT_REPO" add -A && git -C "$ROOT_REPO" commit -qm "root with trailing whitespace"
set +e
run_checker "$ROOT_REPO" >/dev/null 2>&1
STATUS=$?
set -e
if [[ "$STATUS" -eq 1 ]]; then
  pass "root commit is checked against the empty tree (not skipped)"
else
  fail "expected exit 1 for whitespace in a root commit, got ${STATUS}"
fi

if [[ "$FAILED" -ne 0 ]]; then
  echo "FAILED: whitespace-check regression tests" >&2
  exit 1
fi
echo "PASSED: whitespace-check regression tests"
