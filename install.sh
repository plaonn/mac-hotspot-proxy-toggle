#!/bin/bash
set -euo pipefail

LABEL="com.github.plaonn.hotspot-proxy-toggle"
SOURCE_DIR="$(cd "$(/usr/bin/dirname "${BASH_SOURCE[0]}")" && pwd -P)"
INSTALL_ROOT="${HOTSPOT_PROXY_INSTALL_ROOT:-$HOME/.local/share/hotspot-proxy-toggle}"
INSTALL_BIN="$INSTALL_ROOT/bin/hotspot-proxy-toggle"
BIN_LINK="$HOME/.local/bin/hotspot-proxy-toggle"
CONFIG_PATH="${HOTSPOT_PROXY_CONFIG:-$HOME/.config/hotspot-proxy-toggle.conf}"
PLIST_PATH="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG_DIR="$HOME/Library/Logs"
CHECK_INTERVAL_SECONDS="${CHECK_INTERVAL_SECONDS:-60}"

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

write_launch_agent() {
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

install_files() {
  /bin/mkdir -p "$INSTALL_ROOT/bin" "$HOME/.local/bin"
  /usr/bin/install -m 755 "$SOURCE_DIR/bin/hotspot-proxy-toggle" "$INSTALL_BIN"
  /bin/ln -sf "$INSTALL_BIN" "$BIN_LINK"
  printf 'Installed binary: %s\n' "$INSTALL_BIN"
  printf 'Linked command: %s\n' "$BIN_LINK"
}

load_launch_agent() {
  /bin/launchctl bootout "gui/$(/usr/bin/id -u)" "$PLIST_PATH" >/dev/null 2>&1 || true
  /bin/launchctl bootstrap "gui/$(/usr/bin/id -u)" "$PLIST_PATH"
  /bin/launchctl kickstart -k "gui/$(/usr/bin/id -u)/$LABEL"
  printf 'Loaded LaunchAgent: %s\n' "$LABEL"
}

main() {
  install_files
  write_config_if_missing
  write_launch_agent
  load_launch_agent
}

main "$@"
