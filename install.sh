#!/bin/bash
set -euo pipefail

LABEL="com.github.plaonn.hotspot-proxy-toggle"
HELPER_LABEL="$LABEL.helper"
SOURCE_DIR="$(cd "$(/usr/bin/dirname "${BASH_SOURCE[0]}")" && pwd -P)"
INSTALL_ROOT="${HOTSPOT_PROXY_INSTALL_ROOT:-$HOME/.local/share/hotspot-proxy-toggle}"
INSTALL_BIN="$INSTALL_ROOT/bin/hotspot-proxy-toggle"
HELPER_BIN="$INSTALL_ROOT/bin/hotspot-proxy-toggle-helper"
BIN_LINK="$HOME/.local/bin/hotspot-proxy-toggle"
CONFIG_PATH="${HOTSPOT_PROXY_CONFIG:-$HOME/.config/hotspot-proxy-toggle.conf}"
PLIST_PATH="$HOME/Library/LaunchAgents/$LABEL.plist"
HELPER_PLIST_PATH="$HOME/Library/LaunchAgents/$HELPER_LABEL.plist"
LOG_DIR="$HOME/Library/Logs"
CHECK_INTERVAL_SECONDS="${CHECK_INTERVAL_SECONDS:-60}"
HOTSPOT_TRIGGER_MODE="${HOTSPOT_TRIGGER_MODE:-}"
HELPER_DEBOUNCE_SECONDS="${HELPER_DEBOUNCE_SECONDS:-1}"
HELPER_MAX_RUNS="${HELPER_MAX_RUNS:-3}"
HELPER_WINDOW_SECONDS="${HELPER_WINDOW_SECONDS:-10}"
HELPER_WATCHDOG_SECONDS="${HELPER_WATCHDOG_SECONDS:-60}"

resolve_trigger_mode() {
  if [[ -z "$HOTSPOT_TRIGGER_MODE" ]]; then
    HOTSPOT_TRIGGER_MODE="event"
  fi

  case "$HOTSPOT_TRIGGER_MODE" in
    polling|event) ;;
    *)
      printf 'unsupported HOTSPOT_TRIGGER_MODE: %s (supported: polling, event)\n' "$HOTSPOT_TRIGGER_MODE" >&2
      return 64
      ;;
  esac
}

escape_sed_replacement() {
  printf '%s' "$1" | /usr/bin/sed 's/[&|]/\\&/g'
}

write_config_if_missing() {
  /bin/mkdir -p "$(/usr/bin/dirname "$CONFIG_PATH")"
  if [[ -f "$CONFIG_PATH" ]]; then
    printf 'Config exists: %s\n' "$CONFIG_PATH"
    return 0
  fi

  if [[ -z "${PROXY_PORT:-}" ]]; then
    printf 'PROXY_PORT is required for first install\n' >&2
    printf 'Example: PROXY_PORT=1080 ./install.sh\n' >&2
    return 64
  fi

  umask 077
  {
    printf '# hotspot-proxy-toggle config\n'
    printf 'NETWORK_SERVICE=%q\n' "${NETWORK_SERVICE:-Wi-Fi}"
    printf 'WIFI_DEVICE=%q\n' "${WIFI_DEVICE:-}"
    printf 'PROXY_TYPE=%q\n' "${PROXY_TYPE:-socks5}"
    printf 'PROXY_PORT=%q\n' "$PROXY_PORT"
    printf 'HOTSPOT_SSIDS=%q\n' "${HOTSPOT_SSIDS:-}"
    printf 'HOTSPOT_DHCP_MARKERS=%q\n' "${HOTSPOT_DHCP_MARKERS:-ANDROID_METERED}"
    printf 'STRICT_SSID=%q\n' "${STRICT_SSID:-0}"
    printf 'REQUIRE_PROXY_CHECK=%q\n' "${REQUIRE_PROXY_CHECK:-1}"
    printf 'PROXY_CHECK_TIMEOUT=%q\n' "${PROXY_CHECK_TIMEOUT:-1}"
  } >"$CONFIG_PATH"
  printf 'Wrote config: %s\n' "$CONFIG_PATH"
}

write_polling_launch_agent() {
  local escaped_bin escaped_interval escaped_log_dir

  /bin/mkdir -p "$HOME/Library/LaunchAgents" "$LOG_DIR"

  escaped_bin="$(escape_sed_replacement "$INSTALL_BIN")"
  escaped_interval="$(escape_sed_replacement "$CHECK_INTERVAL_SECONDS")"
  escaped_log_dir="$(escape_sed_replacement "$LOG_DIR")"

  /usr/bin/sed \
    -e "s|__INSTALL_BIN__|$escaped_bin|g" \
    -e "s|__CHECK_INTERVAL_SECONDS__|$escaped_interval|g" \
    -e "s|__LOG_DIR__|$escaped_log_dir|g" \
    "$SOURCE_DIR/launchd/$LABEL.plist.in" >"$PLIST_PATH"

  printf 'Wrote LaunchAgent: %s\n' "$PLIST_PATH"
}

write_helper_launch_agent() {
  local escaped_helper escaped_bin escaped_log_dir
  local escaped_debounce escaped_max_runs escaped_window escaped_watchdog

  /bin/mkdir -p "$HOME/Library/LaunchAgents" "$LOG_DIR"

  escaped_helper="$(escape_sed_replacement "$HELPER_BIN")"
  escaped_bin="$(escape_sed_replacement "$INSTALL_BIN")"
  escaped_log_dir="$(escape_sed_replacement "$LOG_DIR")"
  escaped_debounce="$(escape_sed_replacement "$HELPER_DEBOUNCE_SECONDS")"
  escaped_max_runs="$(escape_sed_replacement "$HELPER_MAX_RUNS")"
  escaped_window="$(escape_sed_replacement "$HELPER_WINDOW_SECONDS")"
  escaped_watchdog="$(escape_sed_replacement "$HELPER_WATCHDOG_SECONDS")"

  /usr/bin/sed \
    -e "s|__HELPER_BIN__|$escaped_helper|g" \
    -e "s|__INSTALL_BIN__|$escaped_bin|g" \
    -e "s|__LOG_DIR__|$escaped_log_dir|g" \
    -e "s|__HELPER_DEBOUNCE_SECONDS__|$escaped_debounce|g" \
    -e "s|__HELPER_MAX_RUNS__|$escaped_max_runs|g" \
    -e "s|__HELPER_WINDOW_SECONDS__|$escaped_window|g" \
    -e "s|__HELPER_WATCHDOG_SECONDS__|$escaped_watchdog|g" \
    "$SOURCE_DIR/launchd/$HELPER_LABEL.plist.in" >"$HELPER_PLIST_PATH"

  printf 'Wrote helper LaunchAgent: %s\n' "$HELPER_PLIST_PATH"
}

install_files() {
  /bin/mkdir -p "$INSTALL_ROOT/bin" "$HOME/.local/bin"
  /usr/bin/install -m 755 "$SOURCE_DIR/bin/hotspot-proxy-toggle" "$INSTALL_BIN"
  /bin/ln -sf "$INSTALL_BIN" "$BIN_LINK"
  printf 'Installed binary: %s\n' "$INSTALL_BIN"
  printf 'Linked command: %s\n' "$BIN_LINK"
}

install_helper_file() {
  local output

  if ! output="$(BUILD_DIR="$INSTALL_ROOT/bin" "$SOURCE_DIR/scripts/build-helper.sh" 2>&1)"; then
    printf '%s\n' "$output" >&2
    return 1
  fi
  /bin/chmod 755 "$HELPER_BIN"
  printf 'Installed helper: %s\n' "$output"
}

unload_launch_agent() {
  local plist_path="$1"

  /bin/launchctl bootout "gui/$(/usr/bin/id -u)" "$plist_path" >/dev/null 2>&1 || true
}

cleanup_managed_runtime() {
  unload_launch_agent "$HELPER_PLIST_PATH"
  unload_launch_agent "$PLIST_PATH"
  /bin/rm -f "$HELPER_PLIST_PATH"
  /bin/rm -f "$PLIST_PATH"
  printf 'Stopped managed LaunchAgents\n'
}

load_launch_agent() {
  local label="$1"
  local plist_path="$2"
  local kickstart="${3:-1}"

  unload_launch_agent "$plist_path"
  /bin/launchctl bootstrap "gui/$(/usr/bin/id -u)" "$plist_path"
  if [[ "$kickstart" == "1" ]]; then
    /bin/launchctl kickstart -k "gui/$(/usr/bin/id -u)/$label"
  fi
  printf 'Loaded LaunchAgent: %s\n' "$label"
}

install_event_launch_agent() {
  install_helper_file || return 1
  write_helper_launch_agent || return 1
  load_launch_agent "$HELPER_LABEL" "$HELPER_PLIST_PATH" 0 || return 1
}

install_polling_launch_agent() {
  write_polling_launch_agent || return 1
  load_launch_agent "$LABEL" "$PLIST_PATH" || return 1
}

main() {
  resolve_trigger_mode || return
  cleanup_managed_runtime || return
  install_files || return
  write_config_if_missing || return

  if [[ "$HOTSPOT_TRIGGER_MODE" == "event" ]]; then
    if ! install_event_launch_agent; then
      printf 'Event helper install failed; falling back to polling LaunchAgent\n' >&2
      HOTSPOT_TRIGGER_MODE="polling"
      install_polling_launch_agent || return
    fi
  else
    install_polling_launch_agent || return
  fi

  printf 'Trigger mode: %s\n' "$HOTSPOT_TRIGGER_MODE"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
