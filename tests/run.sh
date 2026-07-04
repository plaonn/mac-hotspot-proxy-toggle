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
  MOCK_DEFAULT_INTERFACE="en0"
  MOCK_IPCONFIG_SUMMARY=""
  PROXY_ACTIONS=()
  PROXY_AVAILABLE=1
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

set_proxy_on() {
  PROXY_ACTIONS+=("on:$1:$PROXY_PORT")
}

set_proxy_off() {
  PROXY_ACTIONS+=("off")
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
    assert_contains "$output" "status=proxy-unavailable router=172.20.10.42 port=1080 action=off" &&
    [[ "${PROXY_ACTIONS[*]-}" == "off" ]]
}

run_enables_proxy_for_available_endpoint() {
  reset_runtime_state
  HOTSPOT_SSIDS="My Phone"
  MOCK_IPCONFIG_SUMMARY=$'Router : 172.20.10.99\nSSID : My Phone'
  PROXY_AVAILABLE=1

  do_run >/dev/null

  [[ "${PROXY_ACTIONS[*]-}" == "on:172.20.10.99:1080" ]]
}

run_test "hotspot by exact SSID" hotspot_by_exact_ssid
run_test "hotspot by DHCP marker fallback" hotspot_by_dhcp_marker_fallback
run_test "reject non-Wi-Fi default route" reject_non_wifi_default_route
run_test "strict SSID disables DHCP marker fallback" dhcp_marker_fallback_respects_strict_ssid
run_test "run disables proxy when endpoint is unavailable" run_disables_proxy_when_endpoint_unavailable
run_test "run enables proxy for available endpoint" run_enables_proxy_for_available_endpoint

printf '\n%s passed, %s failed\n' "$PASS_COUNT" "$FAIL_COUNT"
[[ "$FAIL_COUNT" == "0" ]]
