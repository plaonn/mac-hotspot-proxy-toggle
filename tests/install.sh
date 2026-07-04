#!/bin/bash
# shellcheck disable=SC1091,SC2034
set -euo pipefail

ROOT_DIR="$(cd "$(/usr/bin/dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
TEST_TMP="${TMPDIR:-/tmp}/hotspot-proxy-toggle-install-tests.$$"

mkdir -p "$TEST_TMP"
trap 'rm -rf "$TEST_TMP"' EXIT

# shellcheck source=../install.sh
source "$ROOT_DIR/install.sh"

PASS_COUNT=0
FAIL_COUNT=0
LAST_OUTPUT=""
EVENTS=()
EVENT_RESULT=0

record_pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  printf 'ok - %s\n' "$1"
}

record_fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf 'not ok - %s\n' "$1"
  if [[ -n "$LAST_OUTPUT" ]]; then
    printf '%s\n' "$LAST_OUTPUT" | /usr/bin/sed 's/^/  | /'
  fi
}

run_test() {
  local name="$1"
  shift

  LAST_OUTPUT=""
  if LAST_OUTPUT="$("$@" 2>&1)"; then
    record_pass "$name"
  else
    record_fail "$name"
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"

  [[ "$haystack" == *"$needle"* ]]
}

reset_install_state() {
  HOTSPOT_TRIGGER_MODE=""
  EVENTS=()
  EVENT_RESULT=0
}

install_files() {
  EVENTS+=("install-files")
}

write_config_if_missing() {
  EVENTS+=("write-config")
}

install_event_launch_agent() {
  EVENTS+=("event")
  return "$EVENT_RESULT"
}

install_polling_launch_agent() {
  EVENTS+=("polling")
}

default_install_uses_event_helper() {
  local output

  reset_install_state
  main >"$TEST_TMP/default-event.out" 2>&1
  output="$(<"$TEST_TMP/default-event.out")"

  assert_contains "$output" "Trigger mode: event" &&
    [[ "${EVENTS[*]-}" == "install-files write-config event" ]]
}

event_install_falls_back_to_polling() {
  local output

  reset_install_state
  EVENT_RESULT=1
  main >"$TEST_TMP/fallback.out" 2>&1
  output="$(<"$TEST_TMP/fallback.out")"

  assert_contains "$output" "Event helper install failed; falling back to polling LaunchAgent" &&
    assert_contains "$output" "Trigger mode: polling" &&
    [[ "${EVENTS[*]-}" == "install-files write-config event polling" ]]
}

explicit_polling_skips_event_helper() {
  local output

  reset_install_state
  HOTSPOT_TRIGGER_MODE="polling"
  main >"$TEST_TMP/explicit-polling.out" 2>&1
  output="$(<"$TEST_TMP/explicit-polling.out")"

  assert_contains "$output" "Trigger mode: polling" &&
    [[ "${EVENTS[*]-}" == "install-files write-config polling" ]]
}

unsupported_trigger_mode_is_rejected() {
  local output rc

  reset_install_state
  HOTSPOT_TRIGGER_MODE="invalid"

  set +e
  main >"$TEST_TMP/invalid.out" 2>&1
  rc="$?"
  set -e
  output="$(<"$TEST_TMP/invalid.out")"

  [[ "$rc" == "64" ]] &&
    assert_contains "$output" "unsupported HOTSPOT_TRIGGER_MODE: invalid (supported: polling, event)" &&
    [[ "${EVENTS[*]-}" == "" ]]
}

run_test "default install uses event helper" default_install_uses_event_helper
run_test "event install falls back to polling" event_install_falls_back_to_polling
run_test "explicit polling skips event helper" explicit_polling_skips_event_helper
run_test "unsupported trigger mode is rejected" unsupported_trigger_mode_is_rejected

printf '\n%s passed, %s failed\n' "$PASS_COUNT" "$FAIL_COUNT"
[[ "$FAIL_COUNT" == "0" ]]
