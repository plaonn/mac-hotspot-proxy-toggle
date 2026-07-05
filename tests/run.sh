#!/bin/bash
# shellcheck disable=SC1091,SC2034
# This harness sources the runtime script and assigns globals consumed there.
set -euo pipefail

ROOT_DIR="$(cd "$(/usr/bin/dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SCRIPT="$ROOT_DIR/bin/hotspot-proxy-toggle"
TEST_TMP="${TMPDIR:-/tmp}/hotspot-proxy-toggle-tests.$$"

mkdir -p "$TEST_TMP"
trap 'rm -rf "$TEST_TMP"' EXIT

# shellcheck source=../bin/hotspot-proxy-toggle
source "$SCRIPT"

PASS_COUNT=0
FAIL_COUNT=0
LAST_OUTPUT=""
PROXY_ACTIONS=()
PROXY_AVAILABLE=1
NOTIFICATIONS=()
MOCK_PROXY_CHANGE_ON_OFF=1

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

reset_runtime_state() {
  CONFIG_PATH="$TEST_TMP/missing.conf"
  LOG_PATH="$TEST_TMP/test.log"
  NETWORK_SERVICE="Wi-Fi"
  WIFI_DEVICE="en0"
  HOTSPOT_SSIDS=""
  HOTSPOT_DHCP_MARKERS="ANDROID_METERED"
  PROXY_TYPE="socks5"
  PROXY_PORT="1080"
  STRICT_SSID="0"
  REQUIRE_PROXY_CHECK="1"
  PROXY_CHECK_TIMEOUT="1"
  DRY_RUN="0"
  NOTIFY_ON_CHANGE="0"
  NOTIFICATION_LOCALE="en"
  STATE_PATH="$TEST_TMP/notify-state"
  UI_STATE_PATH="$TEST_TMP/status.json"
  rm -f "$STATE_PATH"
  rm -f "$UI_STATE_PATH"
  PROXY_STATE_CHANGED=0
  MOCK_DEFAULT_INTERFACE="en0"
  MOCK_IPCONFIG_SUMMARY=""
  PROXY_ACTIONS=()
  PROXY_AVAILABLE=1
  NOTIFICATIONS=()
  MOCK_PROXY_CHANGE_ON_OFF=1
}

wifi_device_from_hardware_ports() {
  printf '%s\n' "${MOCK_WIFI_DEVICE:-en0}"
}

default_interface() {
  printf '%s\n' "$MOCK_DEFAULT_INTERFACE"
}

ipconfig_summary() {
  printf '%s\n' "$MOCK_IPCONFIG_SUMMARY"
}

current_proxy_state() {
  printf 'Enabled: No\n'
}

socks5_proxy_available() {
  [[ "$PROXY_AVAILABLE" == "1" ]]
}

proxy_endpoint_available() {
  [[ "$PROXY_AVAILABLE" == "1" ]]
}

set_socks5_proxy_off() {
  PROXY_ACTIONS+=("off:socks5")
  if [[ "$MOCK_PROXY_CHANGE_ON_OFF" == "1" ]]; then
    mark_proxy_changed
  fi
}

set_http_proxy_off() {
  PROXY_ACTIONS+=("off:http")
  if [[ "$MOCK_PROXY_CHANGE_ON_OFF" == "1" ]]; then
    mark_proxy_changed
  fi
}

set_socks5_proxy_on() {
  PROXY_ACTIONS+=("on:socks5:$1:$PROXY_PORT")
  mark_proxy_changed
}

set_http_proxy_on() {
  PROXY_ACTIONS+=("on:http:$1:$PROXY_PORT")
  mark_proxy_changed
}

send_macos_notification() {
  NOTIFICATIONS+=("$1:$2")
}

log() {
  :
}

hotspot_by_exact_ssid() {
  local output rc

  reset_runtime_state
  HOTSPOT_SSIDS="My Phone,Other Phone"
  STRICT_SSID="1"
  MOCK_IPCONFIG_SUMMARY=$'Router : 172.20.10.1\nSSID : My Phone'

  set +e
  output="$(evaluate)"
  rc="$?"
  set -e

  [[ "$rc" == "0" ]] &&
    assert_contains "$output" "status=hotspot" &&
    assert_contains "$output" "reason=ssid" &&
    assert_contains "$output" "router=172.20.10.1"
}

hotspot_by_dhcp_marker_fallback() {
  local output rc

  reset_runtime_state
  HOTSPOT_SSIDS=""
  STRICT_SSID="0"
  MOCK_IPCONFIG_SUMMARY=$'Router : 172.20.10.1\nSSID : Unknown\nANDROID_METERED'

  set +e
  output="$(evaluate)"
  rc="$?"
  set -e

  [[ "$rc" == "0" ]] &&
    assert_contains "$output" "status=hotspot" &&
    assert_contains "$output" "reason=dhcp-marker"
}

reject_non_wifi_default_route() {
  local output rc

  reset_runtime_state
  MOCK_DEFAULT_INTERFACE="en9"
  MOCK_IPCONFIG_SUMMARY=$'Router : 172.20.10.1\nSSID : My Phone\nANDROID_METERED'

  set +e
  output="$(evaluate)"
  rc="$?"
  set -e

  [[ "$rc" == "1" ]] &&
    assert_contains "$output" "status=not-wifi" &&
    assert_contains "$output" "default_interface=en9"
}

dhcp_marker_fallback_respects_strict_ssid() {
  local output rc

  reset_runtime_state
  HOTSPOT_SSIDS="Other Phone"
  STRICT_SSID="1"
  MOCK_IPCONFIG_SUMMARY=$'Router : 172.20.10.1\nSSID : Unknown\nANDROID_METERED'

  set +e
  output="$(evaluate)"
  rc="$?"
  set -e

  [[ "$rc" == "1" ]] &&
    assert_contains "$output" "status=not-hotspot" &&
    assert_contains "$output" "reason=no-match"
}

run_disables_proxy_when_endpoint_unavailable() {
  local output

  reset_runtime_state
  HOTSPOT_SSIDS="My Phone"
  MOCK_IPCONFIG_SUMMARY=$'Router : 172.20.10.42\nSSID : My Phone'
  PROXY_AVAILABLE=0

  do_run >"$TEST_TMP/run-unavailable.out"
  output="$(<"$TEST_TMP/run-unavailable.out")"

  assert_contains "$output" "status=hotspot" &&
    assert_contains "$output" "status=proxy-unavailable proxy_type=socks5 router=172.20.10.42 port=1080 action=off" &&
    [[ "${PROXY_ACTIONS[*]-}" == "off:socks5 off:http" ]] &&
    assert_contains "$(<"$UI_STATE_PATH")" '"kind": "unavailable"' &&
    ! assert_contains "$(<"$UI_STATE_PATH")" "172.20.10.42" &&
    ! assert_contains "$(<"$UI_STATE_PATH")" "My Phone"
}

run_enables_proxy_for_available_endpoint() {
  reset_runtime_state
  HOTSPOT_SSIDS="My Phone"
  MOCK_IPCONFIG_SUMMARY=$'Router : 172.20.10.99\nSSID : My Phone'
  PROXY_AVAILABLE=1

  do_run >/dev/null

  [[ "${PROXY_ACTIONS[*]-}" == "off:http on:socks5:172.20.10.99:1080" ]] &&
    assert_contains "$(<"$UI_STATE_PATH")" '"kind": "on"'
}

run_enables_http_web_proxy_backend() {
  reset_runtime_state
  PROXY_TYPE="http"
  HOTSPOT_SSIDS="My Phone"
  MOCK_IPCONFIG_SUMMARY=$'Router : 172.20.10.88\nSSID : My Phone'
  PROXY_AVAILABLE=1

  do_run >/dev/null

  [[ "${PROXY_ACTIONS[*]-}" == "off:socks5 on:http:172.20.10.88:1080" ]]
}

notification_is_opt_in_for_proxy_enable() {
  reset_runtime_state
  HOTSPOT_SSIDS="My Phone"
  MOCK_IPCONFIG_SUMMARY=$'Router : 172.20.10.99\nSSID : My Phone'
  PROXY_AVAILABLE=1

  do_run >/dev/null

  [[ "${NOTIFICATIONS[*]-}" == "" ]]
}

run_notifies_when_proxy_enabled_and_opted_in() {
  reset_runtime_state
  NOTIFY_ON_CHANGE=1
  HOTSPOT_SSIDS="My Phone"
  MOCK_IPCONFIG_SUMMARY=$'Router : 172.20.10.99\nSSID : My Phone'
  PROXY_AVAILABLE=1

  do_run >/dev/null

  [[ "${NOTIFICATIONS[*]-}" == "✅ Hotspot Proxy On:Traffic is using the hotspot proxy." ]] &&
    [[ "$(<"$STATE_PATH")" == "on:socks5:status=hotspot reason=ssid wifi_device=en0 router=172.20.10.99 ssid=My\\ Phone" ]]
}

run_notifies_when_endpoint_unavailable_and_opted_in() {
  reset_runtime_state
  NOTIFY_ON_CHANGE=1
  HOTSPOT_SSIDS="My Phone"
  MOCK_IPCONFIG_SUMMARY=$'Router : 172.20.10.42\nSSID : My Phone'
  PROXY_AVAILABLE=0

  do_run >/dev/null

  [[ "${NOTIFICATIONS[*]-}" == "⚠️ Hotspot Proxy Unavailable:Hotspot detected, but the proxy server is not responding." ]]
}

run_notifies_when_ssid_context_changes_and_proxy_already_off() {
  reset_runtime_state
  NOTIFY_ON_CHANGE=1
  MOCK_PROXY_CHANGE_ON_OFF=0
  HOTSPOT_SSIDS="Phone"
  printf '%s\n' 'off:socks5:status=not-hotspot wifi_device=en0 router=172.20.10.77 ssid=Coffee reason=no-match' >"$STATE_PATH"
  MOCK_IPCONFIG_SUMMARY=$'Router : 172.20.10.77\nSSID : Office'

  do_run >/dev/null

  [[ "${NOTIFICATIONS[*]-}" == "ℹ️ Hotspot Proxy Idle:Current Wi-Fi is not a configured hotspot." ]] &&
    [[ "$(<"$STATE_PATH")" == "off:socks5:status=not-hotspot wifi_device=en0 router=172.20.10.77 ssid=Office reason=no-match" ]]
}

run_uses_korean_idle_notification_copy() {
  reset_runtime_state
  NOTIFY_ON_CHANGE=1
  NOTIFICATION_LOCALE=ko
  MOCK_PROXY_CHANGE_ON_OFF=0
  HOTSPOT_SSIDS="Phone"
  printf '%s\n' 'off:socks5:status=not-hotspot wifi_device=en0 router=172.20.10.77 ssid=Coffee reason=no-match' >"$STATE_PATH"
  MOCK_IPCONFIG_SUMMARY=$'Router : 172.20.10.77\nSSID : Office'

  do_run >/dev/null

  [[ "${NOTIFICATIONS[*]-}" == "ℹ️ 핫스팟 프록시 대기:현재 Wi-Fi는 설정한 핫스팟이 아닙니다." ]]
}

run_records_not_wifi_without_notification() {
  reset_runtime_state
  NOTIFY_ON_CHANGE=1
  MOCK_PROXY_CHANGE_ON_OFF=0
  MOCK_DEFAULT_INTERFACE="en9"
  MOCK_IPCONFIG_SUMMARY=$'Router : 172.20.10.77\nSSID : Office'

  do_run >/dev/null

  [[ "${NOTIFICATIONS[*]-}" == "" ]] &&
    [[ "$(<"$STATE_PATH")" == "off:socks5:status=not-wifi wifi_device=en0 default_interface=en9" ]]
}

run_records_no_router_without_notification() {
  reset_runtime_state
  NOTIFY_ON_CHANGE=1
  MOCK_PROXY_CHANGE_ON_OFF=0
  MOCK_IPCONFIG_SUMMARY=$'SSID : Office'

  do_run >/dev/null

  [[ "${NOTIFICATIONS[*]-}" == "" ]] &&
    [[ "$(<"$STATE_PATH")" == "off:socks5:status=no-router wifi_device=en0 ssid=Office" ]]
}

run_uses_korean_notification_locale() {
  reset_runtime_state
  NOTIFY_ON_CHANGE=1
  NOTIFICATION_LOCALE=ko
  HOTSPOT_SSIDS="My Phone"
  MOCK_IPCONFIG_SUMMARY=$'Router : 172.20.10.99\nSSID : My Phone'
  PROXY_AVAILABLE=1

  do_run >/dev/null

  [[ "${NOTIFICATIONS[*]-}" == "✅ 핫스팟 프록시 켜짐:현재 트래픽이 핫스팟 프록시를 사용합니다." ]]
}

run_does_not_repeat_context_notification_without_change() {
  reset_runtime_state
  NOTIFY_ON_CHANGE=1
  MOCK_PROXY_CHANGE_ON_OFF=0
  HOTSPOT_SSIDS="Phone"
  printf '%s\n' 'off:socks5:status=not-hotspot wifi_device=en0 router=172.20.10.77 ssid=Office reason=no-match' >"$STATE_PATH"
  MOCK_IPCONFIG_SUMMARY=$'Router : 172.20.10.77\nSSID : Office'

  do_run >/dev/null

  [[ "${NOTIFICATIONS[*]-}" == "" ]]
}

run_disables_all_supported_backends_when_not_hotspot() {
  reset_runtime_state
  HOTSPOT_SSIDS="Other Phone"
  MOCK_IPCONFIG_SUMMARY=$'Router : 172.20.10.77\nSSID : My Phone'

  do_run >/dev/null

  [[ "${PROXY_ACTIONS[*]-}" == "off:socks5 off:http" ]] &&
    assert_contains "$(<"$UI_STATE_PATH")" '"kind": "idle"'
}

off_command_disables_all_supported_backends() {
  local output

  reset_runtime_state
  do_off >"$TEST_TMP/off.out"
  output="$(<"$TEST_TMP/off.out")"

  assert_contains "$output" "status=off action=off" &&
    [[ "${PROXY_ACTIONS[*]-}" == "off:socks5 off:http" ]] &&
    assert_contains "$(<"$UI_STATE_PATH")" '"kind": "off"'
}

unsupported_proxy_type_is_rejected() {
  reset_runtime_state
  PROXY_TYPE="pac"

  set +e
  validate_config >"$TEST_TMP/unsupported.out" 2>&1
  local rc="$?"
  set -e

  [[ "$rc" == "64" ]] &&
    assert_contains "$(<"$TEST_TMP/unsupported.out")" "unsupported PROXY_TYPE: pac (supported: socks5, http)"
}

unsupported_notification_locale_is_rejected() {
  reset_runtime_state
  NOTIFICATION_LOCALE="fr"

  set +e
  validate_config >"$TEST_TMP/unsupported-locale.out" 2>&1
  local rc="$?"
  set -e

  [[ "$rc" == "64" ]] &&
    assert_contains "$(<"$TEST_TMP/unsupported-locale.out")" "unsupported NOTIFICATION_LOCALE: fr (supported: auto, en, ko)"
}

run_test "hotspot by exact SSID" hotspot_by_exact_ssid
run_test "hotspot by DHCP marker fallback" hotspot_by_dhcp_marker_fallback
run_test "reject non-Wi-Fi default route" reject_non_wifi_default_route
run_test "strict SSID disables DHCP marker fallback" dhcp_marker_fallback_respects_strict_ssid
run_test "run disables proxy when endpoint is unavailable" run_disables_proxy_when_endpoint_unavailable
run_test "run enables proxy for available endpoint" run_enables_proxy_for_available_endpoint
run_test "run enables HTTP web proxy backend" run_enables_http_web_proxy_backend
run_test "notification is opt-in for proxy enable" notification_is_opt_in_for_proxy_enable
run_test "run notifies when proxy enabled and opted in" run_notifies_when_proxy_enabled_and_opted_in
run_test "run notifies when endpoint unavailable and opted in" run_notifies_when_endpoint_unavailable_and_opted_in
run_test "run notifies when SSID context changes and proxy already off" run_notifies_when_ssid_context_changes_and_proxy_already_off
run_test "run does not repeat context notification without change" run_does_not_repeat_context_notification_without_change
run_test "run uses Korean idle notification copy" run_uses_korean_idle_notification_copy
run_test "run records not-Wi-Fi without notification" run_records_not_wifi_without_notification
run_test "run records no-router without notification" run_records_no_router_without_notification
run_test "run uses Korean notification locale" run_uses_korean_notification_locale
run_test "run disables all supported backends when not hotspot" run_disables_all_supported_backends_when_not_hotspot
run_test "off command disables all supported backends" off_command_disables_all_supported_backends
run_test "unsupported proxy type is rejected" unsupported_proxy_type_is_rejected
run_test "unsupported notification locale is rejected" unsupported_notification_locale_is_rejected

printf '\n%s passed, %s failed\n' "$PASS_COUNT" "$FAIL_COUNT"
[[ "$FAIL_COUNT" == "0" ]]
