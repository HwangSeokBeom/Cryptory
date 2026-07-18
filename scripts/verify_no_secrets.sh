#!/usr/bin/env bash
#
# verify_no_secrets.sh
#
# Scans git-tracked files for likely committed credentials before build/commit.
# This is a pattern-based scan: it catches common mistakes, it does NOT prove
# the repository is free of secrets. Treat a pass as "no known pattern found",
# never as a security guarantee.
#
# Usage: scripts/verify_no_secrets.sh
# Exit codes: 0 = no findings, 1 = findings reported, 2 = environment error.

set -euo pipefail

section() { printf '\n=== %s ===\n' "$1"; }

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "ERROR: must run inside a git repository" >&2
  exit 2
}
cd "$REPO_ROOT"

FINDINGS=0

report() {
  # $1 = description, $2 = matches (may be empty)
  if [[ -n "$2" ]]; then
    FINDINGS=1
    echo "FOUND: $1"
    printf '%s\n' "$2" | sed 's/^/  /' | head -40
  else
    echo "ok: $1"
  fi
}

section "Forbidden tracked file names"
# Secret carrier files that must never be tracked.
TRACKED_SECRET_FILES="$(git ls-files | grep -E \
  -e '(^|/)\.env(\..+)?$' \
  -e '(^|/)(Local|Auth)?Secrets.*\.xcconfig$' \
  -e 'firebase-adminsdk.*\.json$' \
  -e 'serviceAccount.*\.json$' \
  -e '\.(p12|pem|key|mobileprovision|p8)$' \
  || true)"
report "secret-carrying file names tracked by git" "$TRACKED_SECRET_FILES"

section "Private key blocks"
KEY_BLOCKS="$(git grep -nI -e '-----BEGIN [A-Z ]*PRIVATE KEY-----' -- . ':!scripts/verify_no_secrets.sh' || true)"
report "PEM private key blocks in tracked files" "$KEY_BLOCKS"

section "Bearer tokens and authorization values"
# Literal Authorization headers with a real-looking token (excludes code that
# builds the header from a runtime variable, e.g. "Bearer \(token)").
AUTH_VALUES="$(git grep -nIE 'Authorization["'"'"': ]+Bearer [A-Za-z0-9_\-]{16,}' -- . ':!scripts/verify_no_secrets.sh' || true)"
report "hard-coded Authorization bearer values" "$AUTH_VALUES"

section "Hard-coded API keys and secrets"
# key/secret/token assignments with a long literal value on the same line.
# Xcode variable references ($(...)), placeholders, and test fixtures with
# obviously fake values are filtered.
KEY_ASSIGNMENTS="$(git grep -nIE '(api[_-]?key|api[_-]?secret|access[_-]?key|secret[_-]?key|client[_-]?secret|refresh[_-]?token|access[_-]?token)["'"'"' ]*[:=]["'"'"' ]*[A-Za-z0-9+/_\-]{24,}' -- . \
  ':!scripts/verify_no_secrets.sh' \
  ':!*.md' \
  | grep -vE '\$\(|\$\{|replace-with|example|placeholder|dummy|fixture|test-token|sample' \
  || true)"
report "hard-coded key/secret/token literals" "$KEY_ASSIGNMENTS"

section "Google API keys"
GOOGLE_KEYS="$(git grep -nIE 'AIza[0-9A-Za-z_\-]{35}' -- . ':!scripts/verify_no_secrets.sh' ':!Cryptory/GoogleService-Info.plist' || true)"
report "Google API key literals (outside GoogleService-Info.plist)" "$GOOGLE_KEYS"

section "AWS-style access keys"
AWS_KEYS="$(git grep -nIE '(AKIA|ASIA)[0-9A-Z]{16}' -- . ':!scripts/verify_no_secrets.sh' || true)"
report "AWS-style access key IDs" "$AWS_KEYS"

section "Slack/GitHub/Firebase tokens"
PLATFORM_TOKENS="$(git grep -nIE '(xox[baprs]-[0-9A-Za-z\-]{10,}|ghp_[0-9A-Za-z]{36}|github_pat_[0-9A-Za-z_]{22,}|ya29\.[0-9A-Za-z_\-]{20,})' -- . ':!scripts/verify_no_secrets.sh' || true)"
report "platform token literals" "$PLATFORM_TOKENS"

section "Result"
if [[ "$FINDINGS" -ne 0 ]]; then
  echo "FAILED: potential secrets found. Review the findings above." >&2
  echo "Note: a match may be a false positive; verify before rotating credentials." >&2
  exit 1
fi
echo "PASSED: no known secret patterns found in tracked files."
echo "Reminder: this scan is heuristic and does not guarantee absence of secrets."
