#!/bin/bash
# shellcheck disable=SC2016
set -euo pipefail

ROOT_DIR="$(cd "$(/usr/bin/dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
TEST_TMP="${TMPDIR:-/tmp}/hotspot-proxy-toggle-helper-tests.$$"
HELPER_PID=""

cleanup() {
  if [[ -n "$HELPER_PID" ]] && /bin/kill -0 "$HELPER_PID" 2>/dev/null; then
    /bin/kill "$HELPER_PID" 2>/dev/null || true
    wait "$HELPER_PID" 2>/dev/null || true
  fi
  /bin/rm -rf "$TEST_TMP"
}
trap cleanup EXIT

wait_for_pattern() {
  local pattern="$1"
  local file="$2"
  for _ in {1..100}; do
    if [[ -f "$file" ]] && /usr/bin/grep -q "$pattern" "$file"; then
      return 0
    fi
    /bin/sleep 0.05
  done
  return 1
}

/bin/mkdir -p "$TEST_TMP"
HELPER_BIN="$(BUILD_DIR="$TEST_TMP/build" "$ROOT_DIR/scripts/build-helper.sh")"
FAKE_LOG="$TEST_TMP/command.log"
FAKE_MODE="$TEST_TMP/mode"
export FAKE_LOG FAKE_MODE
/usr/bin/printf '%s\n' "off" >"$FAKE_MODE"

/usr/bin/printf '%s\n' \
  '#!/bin/bash' \
  '/usr/bin/printf "%s\n" "$1" >>"$FAKE_LOG"' \
  'case "$(<"$FAKE_MODE")" in' \
  '  unavailable)' \
  '    /usr/bin/printf "%s\n" "status=hotspot reason=ssid"' \
  '    /usr/bin/printf "%s\n" "status=proxy-unavailable action=off"' \
  '    ;;' \
  '  on) /usr/bin/printf "%s\n" "status=hotspot reason=ssid" ;;' \
  '  *) /usr/bin/printf "%s\n" "status=not-hotspot reason=no-match" ;;' \
  'esac' \
  >"$TEST_TMP/fake-command"
/bin/chmod 755 "$TEST_TMP/fake-command"

"$HELPER_BIN" \
  --command "$TEST_TMP/fake-command" \
  --identity "$TEST_TMP/wifi-identity.json" \
  --debounce 0.05 \
  --max-runs 20 \
  --window 1 \
  --watchdog 0.2 \
  >"$TEST_TMP/helper.log" 2>&1 &
HELPER_PID="$!"

wait_for_pattern "running command; reason=startup" "$TEST_TMP/helper.log"

/usr/bin/printf '%s\n' "unavailable" >"$FAKE_MODE"
/usr/bin/printf '%s\n' '{"wifi_device":"en0","connection_id":"one","ssid":"Hotspot"}' \
  >"$TEST_TMP/wifi-identity.json.tmp"
/bin/mv "$TEST_TMP/wifi-identity.json.tmp" "$TEST_TMP/wifi-identity.json"
wait_for_pattern "running command; reason=identity-change" "$TEST_TMP/helper.log"
wait_for_pattern "started endpoint watchdog" "$TEST_TMP/helper.log"

/usr/bin/printf '%s\n' "on" >"$FAKE_MODE"
wait_for_pattern "running command; reason=endpoint-watchdog" "$TEST_TMP/helper.log"

identity_run_count="$(/usr/bin/grep -c 'running command; reason=identity-change' "$TEST_TMP/helper.log")"
/usr/bin/printf '%s\n' "unrelated" >"$TEST_TMP/status.json"
/bin/sleep 0.3
unchanged_run_count="$(/usr/bin/grep -c 'running command; reason=identity-change' "$TEST_TMP/helper.log")"
[[ "$unchanged_run_count" == "$identity_run_count" ]]

/usr/bin/printf '%s\n' '{"wifi_device":"en0","connection_id":"two","ssid":"Hotspot"}' \
  >"$TEST_TMP/wifi-identity.json.tmp"
/bin/mv "$TEST_TMP/wifi-identity.json.tmp" "$TEST_TMP/wifi-identity.json"

for _ in {1..100}; do
  changed_run_count="$(/usr/bin/grep -c 'running command; reason=identity-change' "$TEST_TMP/helper.log")"
  if ((changed_run_count > identity_run_count)); then
    break
  fi
  /bin/sleep 0.05
done
((changed_run_count > identity_run_count))

printf 'ok - identity cache changes enter helper reconcile scheduler\n'
printf 'ok - hotspot identity starts endpoint watchdog without another network event\n'
printf 'ok - unrelated state files do not trigger identity reconciliation\n'
