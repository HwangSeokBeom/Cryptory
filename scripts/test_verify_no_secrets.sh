#!/usr/bin/env bash
#
# test_verify_no_secrets.sh
#
# Shell regression tests for verify_no_secrets.sh output redaction:
#   1. A repo containing fake credentials fails the scan (exit 1) and the
#      output names path, line number, and rule id.
#   2. The credential VALUES themselves never appear in the output.
#   3. A clean repo passes (exit 0).
#
# Only fake, runtime-assembled tokens are used; no pattern appears literally
# in this file, so the scanner never flags the test itself and no real
# secret is required or exposed.
#
# Usage: scripts/test_verify_no_secrets.sh
# Exit codes: 0 = all cases pass, 1 = a case failed.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCANNER="${SCRIPT_DIR}/verify_no_secrets.sh"
[[ -f "$SCANNER" ]] || { echo "ERROR: scanner not found at $SCANNER" >&2; exit 1; }

FAILED=0
fail() { echo "FAIL: $1" >&2; FAILED=1; }
pass() { echo "ok: $1"; }

make_repo() {
  local dir
  dir="$(mktemp -d)"
  git -C "$dir" init -q
  git -C "$dir" config user.email test@example.invalid
  git -C "$dir" config user.name "redaction test"
  echo "$dir"
}

# --- Case 1 + 2: findings are reported with locations, values are redacted.
DIRTY_REPO="$(make_repo)"
trap 'rm -rf "$DIRTY_REPO" "${CLEAN_REPO:-}"' EXIT

# Fake tokens assembled at runtime so their patterns never appear literally
# in this tracked file.
FAKE_GITHUB_TOKEN="ghp_$(printf 'A%.0s' $(seq 1 36))"
FAKE_AWS_KEY="AKIA$(printf 'Z%.0s' $(seq 1 16))"
FAKE_API_SECRET="fakefakefakefakefakefake$(printf 'Q%.0s' $(seq 1 8))"
{
  printf 'let token = "%s"\n' "$FAKE_GITHUB_TOKEN"
  printf 'let awsAccessKeyId = "%s"\n' "$FAKE_AWS_KEY"
  printf 'api_secret = "%s"\n' "$FAKE_API_SECRET"
} > "$DIRTY_REPO/Config.swift"
git -C "$DIRTY_REPO" add -A

set +e
OUTPUT="$(cd "$DIRTY_REPO" && bash "$SCANNER" 2>&1)"
STATUS=$?
set -e

if [[ "$STATUS" -eq 1 ]]; then
  pass "dirty repo fails the scan with exit 1"
else
  fail "dirty repo should exit 1, got ${STATUS}"
fi

if grep -qE 'Config\.swift:[0-9]+ \[[a-z-]+\]' <<<"$OUTPUT"; then
  pass "finding reports path, line number, and rule id"
else
  fail "finding must be reported as path:line [rule-id]; output was:"$'\n'"$OUTPUT"
fi

for value in "$FAKE_GITHUB_TOKEN" "$FAKE_AWS_KEY" "$FAKE_API_SECRET"; do
  if grep -qF "$value" <<<"$OUTPUT"; then
    fail "scanner output must not echo the credential value (${value:0:6}…)"
  else
    pass "credential value ${value:0:6}… absent from output"
  fi
done

# --- Case 3: a clean repo passes.
CLEAN_REPO="$(make_repo)"
echo "let greeting = \"hello\"" > "$CLEAN_REPO/Safe.swift"
git -C "$CLEAN_REPO" add -A

set +e
CLEAN_OUTPUT="$(cd "$CLEAN_REPO" && bash "$SCANNER" 2>&1)"
CLEAN_STATUS=$?
set -e

if [[ "$CLEAN_STATUS" -eq 0 ]]; then
  pass "clean repo passes the scan"
else
  fail "clean repo should exit 0, got ${CLEAN_STATUS}; output was:"$'\n'"$CLEAN_OUTPUT"
fi

if [[ "$FAILED" -ne 0 ]]; then
  echo "FAILED: secret-scanner redaction regression tests" >&2
  exit 1
fi
echo "PASSED: secret-scanner redaction regression tests"
