#!/usr/bin/env bash
#
# ci_whitespace_check.sh
#
# Runs `git diff --check` over the commits being integrated and FAILS on
# whitespace errors (no `|| true` masking). Selects and validates the
# comparison base:
#
#   Pull requests: BASE_REF (e.g. "main") — fetched explicitly, compared
#                  from the merge base so only the PR's commits are checked.
#   Pushes:        BEFORE_SHA (the previous branch head) when it exists
#                  locally; falls back to HEAD~1, then to the empty tree for
#                  a root commit — the check is never silently disabled.
#
# Usage:
#   BASE_REF=main scripts/ci_whitespace_check.sh            # PR events
#   BEFORE_SHA=<sha> scripts/ci_whitespace_check.sh         # push events
#   scripts/ci_whitespace_check.sh                          # local: HEAD~1
#
# Exit codes: 0 = clean, 1 = whitespace errors, 2 = environment error.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "ERROR: must run inside a git repository" >&2
  exit 2
}
cd "$REPO_ROOT"

BASE_REF="${BASE_REF:-}"
BEFORE_SHA="${BEFORE_SHA:-}"
ZERO_SHA="0000000000000000000000000000000000000000"

if [[ -n "$BASE_REF" ]]; then
  # PR event: make sure the base branch exists locally (CI checkouts can be
  # shallow/single-branch), then diff from the merge base.
  git fetch --no-tags --quiet origin "refs/heads/${BASE_REF}:refs/remotes/origin/${BASE_REF}" || {
    echo "ERROR: cannot fetch base ref '${BASE_REF}' from origin" >&2
    exit 2
  }
  BASE="$(git merge-base "refs/remotes/origin/${BASE_REF}" HEAD)" || {
    echo "ERROR: no merge base between origin/${BASE_REF} and HEAD (shallow clone? use fetch-depth: 0)" >&2
    exit 2
  }
elif [[ -n "$BEFORE_SHA" && "$BEFORE_SHA" != "$ZERO_SHA" ]] \
    && git cat-file -e "${BEFORE_SHA}^{commit}" 2>/dev/null; then
  # Push event with a known previous head.
  BASE="$BEFORE_SHA"
elif git rev-parse --verify --quiet HEAD~1 >/dev/null; then
  # Push to a new branch (before-SHA is all zeros) or local run.
  BASE="$(git rev-parse HEAD~1)"
else
  # Root commit: compare against the empty tree rather than skipping.
  BASE="$(git hash-object -t tree /dev/null)"
fi

# Shell-level validation of the selected base: it must resolve to a real
# object, otherwise fail loudly instead of silently checking nothing.
git rev-parse --verify --quiet "$BASE" >/dev/null || {
  echo "ERROR: resolved base '${BASE}' does not exist" >&2
  exit 2
}

echo "Whitespace check: git diff --check ${BASE}..HEAD"
if ! git diff --check "$BASE" HEAD; then
  echo "FAILED: whitespace errors found in the range above." >&2
  exit 1
fi
echo "PASSED: no whitespace errors."
