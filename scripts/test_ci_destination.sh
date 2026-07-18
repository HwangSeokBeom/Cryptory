#!/usr/bin/env bash
#
# test_ci_destination.sh
#
# Shell-level regression tests for scripts/ci_destination.sh. Hermetic: the
# full-flow cases stub xcodebuild via PATH, so this runs on any machine (the
# original DEST_ID defect only reproduced on a clean GitHub-hosted runner).
#
# Usage: bash scripts/test_ci_destination.sh

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
source "${REPO_ROOT}/scripts/ci_destination.sh"

PASS=0
fail() { echo "FAIL: $1" >&2; exit 1; }
ok() { PASS=$((PASS + 1)); echo "ok: $1"; }

FIXTURE='	Available destinations for the "Cryptory-Dev" scheme:
		{ platform:iOS, id:dvtdevice-DVTiPhonePlaceholder-iphoneos:placeholder, name:Any iOS Device }
		{ platform:iOS Simulator, id:dvtdevice-DVTiOSDeviceSimulatorPlaceholder-iphonesimulator:placeholder, name:Any iOS Simulator Device }
		{ platform:iOS Simulator, arch:arm64, id:78A1DD58-A4FD-4A8D-ABAD-170C8F1382B9, OS:26.4.1, name:iPad (A16) }
		{ platform:iOS Simulator, arch:arm64, id:A033B13E-25AC-4BDE-81B4-41FF4A7A84D2, OS:26.4.1, name:iPhone 17 }
		{ platform:iOS Simulator, arch:arm64, id:D309E475-1799-4CD9-9DC3-64B6CE5FE763, OS:26.5, name:iPhone 17 }
	Ineligible destinations for the "Cryptory-Dev" scheme:
		{ platform:iOS Simulator, id:BAD00000-0000-0000-0000-000000000000, name:iPhone 15, error:iOS 17.0 is not installed }'

# 1. A valid set: the first iPhone line wins; id and name come from that line.
LINE="$(printf '%s\n' "$FIXTURE" | select_destination_line)"
[[ "$(destination_field id "$LINE")" == "A033B13E-25AC-4BDE-81B4-41FF4A7A84D2" ]] \
  || fail "expected first iPhone id, got: $(destination_field id "$LINE")"
[[ "$(destination_field name "$LINE")" == "iPhone 17" ]] \
  || fail "expected name 'iPhone 17', got: $(destination_field name "$LINE")"
ok "valid destination line yields matching id + name"

# 2. Placeholder / generic / ineligible lines are never selected.
NO_IPHONE='		{ platform:iOS Simulator, id:dvtdevice-DVTiOSDeviceSimulatorPlaceholder-iphonesimulator:placeholder, name:Any iOS Simulator Device }
		{ platform:iOS Simulator, id:BAD00000-0000-0000-0000-000000000000, name:iPhone 15, error:iOS 17.0 is not installed }
		{ platform:iOS Simulator, arch:arm64, id:78A1DD58-A4FD-4A8D-ABAD-170C8F1382B9, OS:26.4.1, name:iPad (A16) }'
LINE="$(printf '%s\n' "$NO_IPHONE" | select_destination_line)"
[[ "$(destination_field id "$LINE")" == "78A1DD58-A4FD-4A8D-ABAD-170C8F1382B9" ]] \
  || fail "expected iPad fallback, got: $LINE"
ok "placeholder/generic/ineligible lines are skipped; concrete fallback used"

# 3. Placeholders only -> selection returns nonzero and prints nothing.
PLACEHOLDERS_ONLY='		{ platform:iOS Simulator, id:dvtdevice-DVTiOSDeviceSimulatorPlaceholder-iphonesimulator:placeholder, name:Any iOS Simulator Device }'
if LINE="$(printf '%s\n' "$PLACEHOLDERS_ONLY" | select_destination_line)"; then
  fail "placeholder-only input should not select a destination (got: $LINE)"
fi
[[ -z "$LINE" ]] || fail "placeholder-only input printed output: $LINE"
ok "placeholder-only destination set is rejected"

# Stub xcodebuild for the full select_simulator_destination flow.
STUB_DIR="$(mktemp -d)"
trap 'rm -rf "$STUB_DIR"' EXIT
cat > "${STUB_DIR}/xcodebuild" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  *-showdestinations*) cat "${STUB_DESTINATIONS_FILE}" ;;
  *-version*) echo "Xcode 0.0 (stub)" ;;
esac
STUB
chmod +x "${STUB_DIR}/xcodebuild"

# 4. Full flow under set -u: DEST_ID/DEST_NAME are set and non-empty.
printf '%s\n' "$FIXTURE" > "${STUB_DIR}/dest.txt"
OUT="$(
  set -euo pipefail
  PATH="${STUB_DIR}:${PATH}" STUB_DESTINATIONS_FILE="${STUB_DIR}/dest.txt" \
    select_simulator_destination Cryptory.xcodeproj Cryptory-Dev
  echo "id=${DEST_ID} name=${DEST_NAME}"
)" || fail "select_simulator_destination failed on a valid destination set"
[[ "$OUT" == "id=A033B13E-25AC-4BDE-81B4-41FF4A7A84D2 name=iPhone 17" ]] \
  || fail "unexpected full-flow result: $OUT"
ok "full flow sets DEST_ID and DEST_NAME under set -u"

# 5. Empty destination set: fails with diagnostics, no unbound-variable error.
printf '%s\n' "$PLACEHOLDERS_ONLY" > "${STUB_DIR}/dest.txt"
set +e
ERR="$(
  set -euo pipefail
  PATH="${STUB_DIR}:${PATH}" STUB_DESTINATIONS_FILE="${STUB_DIR}/dest.txt" \
    select_simulator_destination Cryptory.xcodeproj Cryptory-Dev 2>&1
)"
RC=$?
set -e
[[ $RC -ne 0 ]] || fail "empty destination set should fail"
grep -q 'ERROR: no usable iOS Simulator destination found' <<< "$ERR" \
  || fail "missing clear error message; got: $ERR"
grep -q 'Scheme: Cryptory-Dev' <<< "$ERR" || fail "diagnostics missing scheme"
grep -q 'Xcode 0.0 (stub)' <<< "$ERR" || fail "diagnostics missing Xcode version"
grep -q 'Any iOS Simulator Device' <<< "$ERR" \
  || fail "diagnostics missing full -showdestinations output"
if grep -q 'unbound variable' <<< "$ERR"; then fail "unbound variable leaked: $ERR"; fi
ok "empty destination set fails clearly with diagnostics (no unbound variable)"

echo
echo "All ${PASS} destination-selection tests passed."
