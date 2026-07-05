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
EVENT_HELPER_RESULT=0
EVENT_PLIST_RESULT=0
HELPER_LOAD_RESULT=0
POLLING_LOAD_RESULT=0
MENU_BAR_RESULT=0
MENU_BAR_PLIST_RESULT=0
MENU_BAR_LOAD_RESULT=0
APP_RESULT=0

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
  HOTSPOT_MENU_BAR="0"
  HOTSPOT_APP="1"
  APP_INSTALLED=0
  EVENTS=()
  EVENT_HELPER_RESULT=0
  EVENT_PLIST_RESULT=0
  HELPER_LOAD_RESULT=0
  POLLING_LOAD_RESULT=0
  MENU_BAR_RESULT=0
  MENU_BAR_PLIST_RESULT=0
  MENU_BAR_LOAD_RESULT=0
  APP_RESULT=0
}

install_files() {
  EVENTS+=("install-files")
}

cleanup_managed_runtime() {
  EVENTS+=("cleanup")
}

write_config_if_missing() {
  EVENTS+=("write-config")
}

install_helper_file() {
  EVENTS+=("event-helper")
  return "$EVENT_HELPER_RESULT"
}

write_helper_launch_agent() {
  EVENTS+=("event-plist")
  return "$EVENT_PLIST_RESULT"
}

write_polling_launch_agent() {
  EVENTS+=("polling-plist")
}

install_menu_bar_file() {
  EVENTS+=("menu-bar")
  return "$MENU_BAR_RESULT"
}

install_app_bundle() {
  EVENTS+=("app")
  if [[ "$APP_RESULT" == "0" ]]; then
    APP_INSTALLED=1
  fi
  return "$APP_RESULT"
}

write_menu_bar_launch_agent() {
  EVENTS+=("menu-bar-plist")
  return "$MENU_BAR_PLIST_RESULT"
}

load_launch_agent() {
  local label="$1"

  if [[ "$label" == "$HELPER_LABEL" ]]; then
    EVENTS+=("helper-load")
    return "$HELPER_LOAD_RESULT"
  fi

  if [[ "$label" == "$MENU_BAR_LABEL" ]]; then
    EVENTS+=("menu-bar-load")
    return "$MENU_BAR_LOAD_RESULT"
  fi

  EVENTS+=("polling-load")
  return "$POLLING_LOAD_RESULT"
}

default_install_uses_event_helper() {
  local output

  reset_install_state
  main >"$TEST_TMP/default-event.out" 2>&1
  output="$(<"$TEST_TMP/default-event.out")"

  assert_contains "$output" "Trigger mode: event" &&
    assert_contains "$output" "Menu bar: disabled" &&
    assert_contains "$output" "App: " &&
    [[ "${EVENTS[*]-}" == "cleanup install-files write-config app event-helper event-plist helper-load" ]]
}

menu_bar_opt_in_installs_companion() {
  local output

  reset_install_state
  HOTSPOT_MENU_BAR=1
  main >"$TEST_TMP/menu-bar.out" 2>&1
  output="$(<"$TEST_TMP/menu-bar.out")"

  assert_contains "$output" "Trigger mode: event" &&
    assert_contains "$output" "Menu bar: enabled" &&
    [[ "${EVENTS[*]-}" == "cleanup install-files write-config app event-helper event-plist helper-load menu-bar menu-bar-plist menu-bar-load" ]]
}

app_build_failure_keeps_core_install() {
  local output

  reset_install_state
  APP_RESULT=1
  main >"$TEST_TMP/app-failure.out" 2>&1
  output="$(<"$TEST_TMP/app-failure.out")"

  assert_contains "$output" "MHP.app install failed; continuing without Finder app" &&
    assert_contains "$output" "Trigger mode: event" &&
    assert_contains "$output" "App: disabled" &&
    [[ "${EVENTS[*]-}" == "cleanup install-files write-config app event-helper event-plist helper-load" ]]
}

menu_bar_build_failure_keeps_core_install() {
  local output

  reset_install_state
  HOTSPOT_MENU_BAR=1
  MENU_BAR_RESULT=1
  main >"$TEST_TMP/menu-bar-failure.out" 2>&1
  output="$(<"$TEST_TMP/menu-bar-failure.out")"

  assert_contains "$output" "Menu bar diagnostic: failed to build or install companion binary" &&
    assert_contains "$output" "Menu bar companion install failed; continuing without menu bar item" &&
    assert_contains "$output" "Trigger mode: event" &&
    assert_contains "$output" "Menu bar: disabled" &&
    [[ "${EVENTS[*]-}" == "cleanup install-files write-config app event-helper event-plist helper-load menu-bar" ]]
}

event_helper_build_failure_falls_back_to_polling() {
  local output

  reset_install_state
  EVENT_HELPER_RESULT=1
  main >"$TEST_TMP/build-fallback.out" 2>&1
  output="$(<"$TEST_TMP/build-fallback.out")"

  assert_contains "$output" "Event helper diagnostic: failed to build or install helper binary" &&
    assert_contains "$output" "Hint: install Xcode Command Line Tools or run scripts/build-helper.sh for details" &&
    assert_contains "$output" "Event helper install failed; falling back to polling LaunchAgent" &&
    assert_contains "$output" "Installed polling fallback; retry event mode after fixing the diagnostic above by running ./install.sh" &&
    assert_contains "$output" "Trigger mode: polling" &&
    [[ "${EVENTS[*]-}" == "cleanup install-files write-config app event-helper polling-plist polling-load" ]]
}

event_plist_failure_falls_back_to_polling() {
  local output

  reset_install_state
  EVENT_PLIST_RESULT=1
  main >"$TEST_TMP/plist-fallback.out" 2>&1
  output="$(<"$TEST_TMP/plist-fallback.out")"

  assert_contains "$output" "Event helper diagnostic: failed to write helper LaunchAgent plist:" &&
    assert_contains "$output" "Event helper install failed; falling back to polling LaunchAgent" &&
    assert_contains "$output" "Trigger mode: polling" &&
    [[ "${EVENTS[*]-}" == "cleanup install-files write-config app event-helper event-plist polling-plist polling-load" ]]
}

event_launchctl_failure_falls_back_to_polling() {
  local output

  reset_install_state
  HELPER_LOAD_RESULT=1
  main >"$TEST_TMP/load-fallback.out" 2>&1
  output="$(<"$TEST_TMP/load-fallback.out")"

  assert_contains "$output" "Event helper diagnostic: failed to load helper LaunchAgent:" &&
    assert_contains "$output" 'Hint: inspect with launchctl print "gui/' &&
    assert_contains "$output" '/com.github.plaonn.hotspot-proxy-toggle.helper"' &&
  assert_contains "$output" "Event helper install failed; falling back to polling LaunchAgent" &&
    assert_contains "$output" "Trigger mode: polling" &&
    [[ "${EVENTS[*]-}" == "cleanup install-files write-config app event-helper event-plist helper-load polling-plist polling-load" ]]
}

explicit_polling_skips_event_helper() {
  local output

  reset_install_state
  HOTSPOT_TRIGGER_MODE="polling"
  main >"$TEST_TMP/explicit-polling.out" 2>&1
  output="$(<"$TEST_TMP/explicit-polling.out")"

  assert_contains "$output" "Trigger mode: polling" &&
    [[ "${EVENTS[*]-}" == "cleanup install-files write-config app polling-plist polling-load" ]]
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
run_test "menu bar opt-in installs companion" menu_bar_opt_in_installs_companion
run_test "app build failure keeps core install" app_build_failure_keeps_core_install
run_test "menu bar build failure keeps core install" menu_bar_build_failure_keeps_core_install
run_test "event helper build failure falls back to polling" event_helper_build_failure_falls_back_to_polling
run_test "event plist failure falls back to polling" event_plist_failure_falls_back_to_polling
run_test "event launchctl failure falls back to polling" event_launchctl_failure_falls_back_to_polling
run_test "explicit polling skips event helper" explicit_polling_skips_event_helper
run_test "unsupported trigger mode is rejected" unsupported_trigger_mode_is_rejected

printf '\n%s passed, %s failed\n' "$PASS_COUNT" "$FAIL_COUNT"
[[ "$FAIL_COUNT" == "0" ]]
