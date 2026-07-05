#!/bin/bash
set -euo pipefail

LABEL="com.github.plaonn.hotspot-proxy-toggle"
HELPER_LABEL="$LABEL.helper"
MENU_BAR_LABEL="$LABEL.menu"
SOURCE_DIR="$(cd "$(/usr/bin/dirname "${BASH_SOURCE[0]}")" && pwd -P)"
INSTALL_ROOT="${HOTSPOT_PROXY_INSTALL_ROOT:-$HOME/.local/share/hotspot-proxy-toggle}"
INSTALL_BIN="$INSTALL_ROOT/bin/hotspot-proxy-toggle"
HELPER_BIN="$INSTALL_ROOT/bin/hotspot-proxy-toggle-helper"
MENU_BAR_BIN="$INSTALL_ROOT/bin/hotspot-proxy-toggle-menu"
BIN_LINK="$HOME/.local/bin/hotspot-proxy-toggle"
CONFIG_PATH="${HOTSPOT_PROXY_CONFIG:-$HOME/.config/hotspot-proxy-toggle.conf}"
PLIST_PATH="$HOME/Library/LaunchAgents/$LABEL.plist"
HELPER_PLIST_PATH="$HOME/Library/LaunchAgents/$HELPER_LABEL.plist"
MENU_BAR_PLIST_PATH="$HOME/Library/LaunchAgents/$MENU_BAR_LABEL.plist"
LOG_DIR="$HOME/Library/Logs"
UI_STATE_PATH="${HOTSPOT_PROXY_UI_STATE:-$HOME/Library/Application Support/hotspot-proxy-toggle/status.json}"
CHECK_INTERVAL_SECONDS="${CHECK_INTERVAL_SECONDS:-60}"
HOTSPOT_TRIGGER_MODE="${HOTSPOT_TRIGGER_MODE:-}"
HOTSPOT_MENU_BAR="${HOTSPOT_MENU_BAR:-0}"
HOTSPOT_APP="${HOTSPOT_APP:-1}"
APP_INSTALL_DIR="${HOTSPOT_APP_INSTALL_DIR:-$HOME/Applications}"
APP_INSTALL_PATH="$APP_INSTALL_DIR/MHP.app"
MENU_BAR_REFRESH_SECONDS="${MENU_BAR_REFRESH_SECONDS:-30}"
MENU_BAR_TITLE="${MENU_BAR_TITLE:-}"
MENU_BAR_INSTALLED=0
APP_INSTALLED=0
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
    printf 'NETWORK_SERVICE=%q\n' "${NETWORK_SERVICE:-}"
    printf 'WIFI_DEVICE=%q\n' "${WIFI_DEVICE:-}"
    printf 'PROXY_TYPE=%q\n' "${PROXY_TYPE:-socks5}"
    printf 'PROXY_PORT=%q\n' "$PROXY_PORT"
    printf 'HOTSPOT_SSID=%q\n' "${HOTSPOT_SSID:-}"
    printf 'REQUIRE_PROXY_CHECK=%q\n' "${REQUIRE_PROXY_CHECK:-1}"
    printf 'PROXY_CHECK_TIMEOUT=%q\n' "${PROXY_CHECK_TIMEOUT:-1}"
    printf 'NOTIFY_ON_CHANGE=%q\n' "${NOTIFY_ON_CHANGE:-0}"
    printf 'LANGUAGE=%q\n' "${LANGUAGE:-auto}"
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

write_menu_bar_launch_agent() {
  local escaped_menu escaped_bin escaped_config escaped_log_dir escaped_state escaped_refresh escaped_title

  /bin/mkdir -p "$HOME/Library/LaunchAgents" "$LOG_DIR"

  escaped_menu="$(escape_sed_replacement "$MENU_BAR_BIN")"
  escaped_bin="$(escape_sed_replacement "$INSTALL_BIN")"
  escaped_config="$(escape_sed_replacement "$CONFIG_PATH")"
  escaped_log_dir="$(escape_sed_replacement "$LOG_DIR")"
  escaped_state="$(escape_sed_replacement "$UI_STATE_PATH")"
  escaped_refresh="$(escape_sed_replacement "$MENU_BAR_REFRESH_SECONDS")"
  escaped_title="$(escape_sed_replacement "$MENU_BAR_TITLE")"

  /usr/bin/sed \
    -e "s|__MENU_BIN__|$escaped_menu|g" \
    -e "s|__INSTALL_BIN__|$escaped_bin|g" \
    -e "s|__CONFIG_PATH__|$escaped_config|g" \
    -e "s|__LOG_DIR__|$escaped_log_dir|g" \
    -e "s|__UI_STATE_PATH__|$escaped_state|g" \
    -e "s|__MENU_REFRESH_SECONDS__|$escaped_refresh|g" \
    -e "s|__MENU_BAR_TITLE__|$escaped_title|g" \
    "$SOURCE_DIR/launchd/$MENU_BAR_LABEL.plist.in" >"$MENU_BAR_PLIST_PATH"

  printf 'Wrote menu bar LaunchAgent: %s\n' "$MENU_BAR_PLIST_PATH"
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

install_menu_bar_file() {
  local output

  if ! output="$(BUILD_DIR="$INSTALL_ROOT/bin" "$SOURCE_DIR/scripts/build-menu-bar.sh" 2>&1)"; then
    printf '%s\n' "$output" >&2
    return 1
  fi
  /bin/chmod 755 "$MENU_BAR_BIN"
  printf 'Installed menu bar companion: %s\n' "$output"
}

install_app_bundle() {
  local app_output app_path

  if [[ "$HOTSPOT_APP" != "1" ]]; then
    return 0
  fi

  if ! app_output="$(APP_PATH="$INSTALL_ROOT/MHP.app" "$SOURCE_DIR/scripts/build-app.sh" 2>&1)"; then
    printf '%s\n' "$app_output" >&2
    printf 'App diagnostic: failed to build MHP.app\n' >&2
    printf 'Hint: install Xcode Command Line Tools or run scripts/build-app.sh for details\n' >&2
    return 1
  fi

  app_path="$(printf '%s\n' "$app_output" | /usr/bin/tail -n 1)"
  if [[ ! -d "$app_path" ]]; then
    printf '%s\n' "$app_output" >&2
    printf 'App diagnostic: build output did not end with an app bundle path\n' >&2
    return 1
  fi

  /bin/mkdir -p "$APP_INSTALL_DIR"
  /bin/rm -rf "$APP_INSTALL_PATH"
  /bin/cp -R "$app_path" "$APP_INSTALL_PATH"
  APP_INSTALLED=1
  printf 'Installed app: %s\n' "$APP_INSTALL_PATH"
}

unload_launch_agent() {
  local plist_path="$1"

  /bin/launchctl bootout "gui/$(/usr/bin/id -u)" "$plist_path" >/dev/null 2>&1 || true
}

cleanup_managed_runtime() {
  unload_launch_agent "$MENU_BAR_PLIST_PATH"
  unload_launch_agent "$HELPER_PLIST_PATH"
  unload_launch_agent "$PLIST_PATH"
  /bin/rm -f "$MENU_BAR_PLIST_PATH"
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
  if ! install_helper_file; then
    printf 'Event helper diagnostic: failed to build or install helper binary\n' >&2
    printf 'Hint: install Xcode Command Line Tools or run scripts/build-helper.sh for details\n' >&2
    return 1
  fi

  if ! write_helper_launch_agent; then
    printf 'Event helper diagnostic: failed to write helper LaunchAgent plist: %s\n' "$HELPER_PLIST_PATH" >&2
    return 1
  fi

  if ! load_launch_agent "$HELPER_LABEL" "$HELPER_PLIST_PATH" 0; then
    printf 'Event helper diagnostic: failed to load helper LaunchAgent: %s\n' "$HELPER_LABEL" >&2
    printf 'Hint: inspect with launchctl print "gui/%s/%s"\n' "$(/usr/bin/id -u)" "$HELPER_LABEL" >&2
    return 1
  fi
}

install_polling_launch_agent() {
  write_polling_launch_agent || return 1
  load_launch_agent "$LABEL" "$PLIST_PATH" || return 1
}

install_menu_bar_launch_agent() {
  if [[ "$HOTSPOT_MENU_BAR" != "1" ]]; then
    return 0
  fi

  if ! install_menu_bar_file; then
    printf 'Menu bar diagnostic: failed to build or install companion binary\n' >&2
    printf 'Hint: install Xcode Command Line Tools or run scripts/build-menu-bar.sh for details\n' >&2
    return 1
  fi

  if ! write_menu_bar_launch_agent; then
    printf 'Menu bar diagnostic: failed to write LaunchAgent plist: %s\n' "$MENU_BAR_PLIST_PATH" >&2
    return 1
  fi

  if ! load_launch_agent "$MENU_BAR_LABEL" "$MENU_BAR_PLIST_PATH"; then
    printf 'Menu bar diagnostic: failed to load LaunchAgent: %s\n' "$MENU_BAR_LABEL" >&2
    printf 'Hint: inspect with launchctl print "gui/%s/%s"\n' "$(/usr/bin/id -u)" "$MENU_BAR_LABEL" >&2
    return 1
  fi

  MENU_BAR_INSTALLED=1
}

main() {
  resolve_trigger_mode || return
  cleanup_managed_runtime || return
  install_files || return
  write_config_if_missing || return
  if ! install_app_bundle; then
    printf 'MHP.app install failed; continuing without Finder app\n' >&2
  fi

  if [[ "$HOTSPOT_TRIGGER_MODE" == "event" ]]; then
    if ! install_event_launch_agent; then
      printf 'Event helper install failed; falling back to polling LaunchAgent\n' >&2
      HOTSPOT_TRIGGER_MODE="polling"
      install_polling_launch_agent || return
      printf 'Installed polling fallback; retry event mode after fixing the diagnostic above by running ./install.sh\n' >&2
    fi
  else
    install_polling_launch_agent || return
  fi

  if ! install_menu_bar_launch_agent; then
    printf 'Menu bar companion install failed; continuing without menu bar item\n' >&2
  fi

  printf 'Trigger mode: %s\n' "$HOTSPOT_TRIGGER_MODE"
  printf 'Menu bar: %s\n' "$([[ "$MENU_BAR_INSTALLED" == "1" ]] && printf 'enabled' || printf 'disabled')"
  printf 'App: %s\n' "$([[ "$APP_INSTALLED" == "1" ]] && printf '%s' "$APP_INSTALL_PATH" || printf 'disabled')"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
