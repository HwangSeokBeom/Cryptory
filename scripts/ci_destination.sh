#!/usr/bin/env bash
#
# ci_destination.sh
#
# Shared simulator-destination selection for ci_build.sh / ci_test.sh.
# Source this file; it defines functions only and is safe under
# `set -euo pipefail`.
#
# Selection rules (applied to `xcodebuild -showdestinations` output):
#   - only `platform:iOS Simulator` lines
#   - never placeholder / "Any iOS Simulator Device" / ineligible (error:) lines
#   - prefer the first iPhone destination, fall back to any concrete simulator
#   - id and name always come from the SAME line, so the pair is consistent
#     across duplicate model names on different runtimes

# Reads `-showdestinations` output on stdin; prints the single chosen
# destination line, or prints nothing and returns 1 if none qualify.
select_destination_line() {
  local candidates iphone
  candidates="$(grep 'platform:iOS Simulator' \
    | grep -v 'placeholder' \
    | grep -v 'Any iOS Simulator Device' \
    | grep -v 'error:' || true)"
  [[ -n "$candidates" ]] || return 1
  iphone="$(printf '%s\n' "$candidates" | grep 'name:iPhone' || true)"
  if [[ -n "$iphone" ]]; then
    printf '%s\n' "$iphone" | head -1
  else
    printf '%s\n' "$candidates" | head -1
  fi
}

# destination_field <field> <line> — prints the value of id/name/OS from one
# destination line, trimmed; prints nothing if the field is absent.
destination_field() {
  local field="$1" line="$2"
  printf '%s\n' "$line" \
    | sed -En "s/.*${field}:([^,}]+).*/\1/p" \
    | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

# select_simulator_destination <project> <scheme>
# Sets DEST_ID and DEST_NAME (from the same destination line) or prints full
# diagnostics to stderr and returns 2.
select_simulator_destination() {
  local project="$1" scheme="$2"
  local destinations line
  destinations="$(xcodebuild -showdestinations -project "$project" -scheme "$scheme" 2>/dev/null || true)"
  line="$(printf '%s\n' "$destinations" | select_destination_line || true)"
  DEST_ID="$(destination_field id "$line")"
  DEST_NAME="$(destination_field name "$line")"
  if [[ -z "$DEST_ID" || -z "$DEST_NAME" ]]; then
    {
      echo "ERROR: no usable iOS Simulator destination found."
      echo "Scheme: ${scheme}"
      echo "Xcode: $(xcodebuild -version 2>/dev/null | tr '\n' ' ' || echo 'xcodebuild unavailable')"
      echo "Configured IPHONEOS_DEPLOYMENT_TARGET:"
      xcodebuild -showBuildSettings -project "$project" -scheme "$scheme" 2>/dev/null \
        | grep -m1 'IPHONEOS_DEPLOYMENT_TARGET' || echo "  (unavailable)"
      echo "Installed SDKs (xcodebuild -showsdks):"
      xcodebuild -showsdks 2>/dev/null || echo "  (unavailable)"
      echo "Installed simulator runtimes (xcrun simctl list runtimes):"
      xcrun simctl list runtimes 2>/dev/null || echo "  (unavailable)"
      echo "Full xcodebuild -showdestinations output:"
      printf '%s\n' "$destinations"
      echo "Hint: an empty destination list usually means no installed simulator"
      echo "runtime satisfies the project's minimum deployment target."
    } >&2
    return 2
  fi
}
