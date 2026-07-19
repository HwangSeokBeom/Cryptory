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

# Output redaction: findings are reported as "path:line [rule-id]" only.
# The matched source line is NEVER printed — echoing it would leak the very
# credential the scan exists to catch (into terminals and CI logs).
redact_locations() {
  # stdin: git grep -n output ("path:line:content"); stdout: "path:line".
  cut -d: -f1,2
}

report() {
  # $1 = rule id, $2 = redacted description, $3 = locations (may be empty;
  # "path:line" or bare paths — never file content).
  if [[ -n "$3" ]]; then
    FINDINGS=1
    echo "FOUND [$1]: $2"
    printf '%s\n' "$3" | sed "s/^/  /;s/\$/ [$1]/" | head -40
  else
    echo "ok [$1]: $2"
  fi
}

section "Forbidden tracked file names"
# Secret carrier files that must never be tracked. Matches are file names,
# not contents — safe to print as-is.
TRACKED_SECRET_FILES="$(git ls-files | grep -E \
  -e '(^|/)\.env(\..+)?$' \
  -e '(^|/)(Local|Auth)?Secrets.*\.xcconfig$' \
  -e 'firebase-adminsdk.*\.json$' \
  -e 'serviceAccount.*\.json$' \
  -e '\.(p12|pem|key|mobileprovision|p8)$' \
  || true)"
report "tracked-secret-file" "secret-carrying file names tracked by git" "$TRACKED_SECRET_FILES"

section "Private key blocks"
KEY_BLOCKS="$(git grep -nI -e '-----BEGIN [A-Z ]*PRIVATE KEY-----' -- . ':!scripts/verify_no_secrets.sh' ':!scripts/test_verify_no_secrets.sh' | redact_locations || true)"
report "pem-private-key" "PEM private key block in a tracked file" "$KEY_BLOCKS"

section "Bearer tokens and authorization values"
# Literal Authorization headers with a real-looking token (excludes code that
# builds the header from a runtime variable, e.g. "Bearer \(token)").
AUTH_VALUES="$(git grep -nIE 'Authorization["'"'"': ]+Bearer [A-Za-z0-9_\-]{16,}' -- . ':!scripts/verify_no_secrets.sh' ':!scripts/test_verify_no_secrets.sh' | redact_locations || true)"
report "authorization-bearer" "hard-coded Authorization bearer value" "$AUTH_VALUES"

section "Hard-coded API keys and secrets"
# key/secret/token assignments with a long literal value on the same line.
# Xcode variable references ($(...)), placeholders, and test fixtures with
# obviously fake values are filtered.
KEY_ASSIGNMENTS="$(git grep -nIE '(api[_-]?key|api[_-]?secret|access[_-]?key|secret[_-]?key|client[_-]?secret|refresh[_-]?token|access[_-]?token)["'"'"' ]*[:=]["'"'"' ]*[A-Za-z0-9+/_\-]{24,}' -- . \
  ':!scripts/verify_no_secrets.sh' \
  ':!scripts/test_verify_no_secrets.sh' \
  ':!*.md' \
  | grep -vE '\$\(|\$\{|replace-with|example|placeholder|dummy|fixture|test-token|sample' \
  | redact_locations \
  || true)"
report "key-secret-literal" "hard-coded key/secret/token literal" "$KEY_ASSIGNMENTS"

section "Google API keys"
GOOGLE_KEYS="$(git grep -nIE 'AIza[0-9A-Za-z_\-]{35}' -- . ':!scripts/verify_no_secrets.sh' ':!scripts/test_verify_no_secrets.sh' ':!Cryptory/GoogleService-Info.plist' | redact_locations || true)"
report "google-api-key" "Google API key literal (outside GoogleService-Info.plist)" "$GOOGLE_KEYS"

section "AWS-style access keys"
AWS_KEYS="$(git grep -nIE '(AKIA|ASIA)[0-9A-Z]{16}' -- . ':!scripts/verify_no_secrets.sh' ':!scripts/test_verify_no_secrets.sh' | redact_locations || true)"
report "aws-access-key" "AWS-style access key ID" "$AWS_KEYS"

section "Slack/GitHub/Firebase tokens"
PLATFORM_TOKENS="$(git grep -nIE '(xox[baprs]-[0-9A-Za-z\-]{10,}|ghp_[0-9A-Za-z]{36}|github_pat_[0-9A-Za-z_]{22,}|ya29\.[0-9A-Za-z_\-]{20,})' -- . ':!scripts/verify_no_secrets.sh' ':!scripts/test_verify_no_secrets.sh' | redact_locations || true)"
report "platform-token" "platform token literal" "$PLATFORM_TOKENS"

section "Result"
if [[ "$FINDINGS" -ne 0 ]]; then
  echo "FAILED: potential secrets found. Review the findings above." >&2
  echo "Note: a match may be a false positive; verify before rotating credentials." >&2
  exit 1
fi
echo "PASSED: no known secret patterns found in tracked files."
echo "Reminder: this scan is heuristic and does not guarantee absence of secrets."
