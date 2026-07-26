#!/bin/bash
set -euo pipefail

LABEL="com.github.plaonn.hotspot-proxy-toggle"
HELPER_LABEL="$LABEL.helper"
MENU_BAR_LABEL="$LABEL.menu"
INSTALL_ROOT="${HOTSPOT_PROXY_INSTALL_ROOT:-$HOME/.local/share/hotspot-proxy-toggle}"
APP_INSTALL_PATH="${HOTSPOT_APP_INSTALL_PATH:-$HOME/Applications/Mac Hotspot Proxy Toggle.app}"
LEGACY_APP_INSTALL_PATH="$HOME/Applications/MHP.app"
BIN_LINK="$HOME/.local/bin/hotspot-proxy-toggle"
CONFIG_PATH="${HOTSPOT_PROXY_CONFIG:-$HOME/.config/hotspot-proxy-toggle.conf}"
PLIST_PATH="$HOME/Library/LaunchAgents/$LABEL.plist"
HELPER_PLIST_PATH="$HOME/Library/LaunchAgents/$HELPER_LABEL.plist"
MENU_BAR_PLIST_PATH="$HOME/Library/LaunchAgents/$MENU_BAR_LABEL.plist"

stop_app_process_at_path() {
  local app_path="$1"
  local executable="$app_path/Contents/MacOS/hotspot-proxy-toggle-menu"
  local pid command

  [[ -d "$app_path" ]] || return 0

  while IFS= read -r pid; do
    [[ -n "$pid" ]] || continue
    command="$(/bin/ps -p "$pid" -o command= 2>/dev/null || true)"
    if [[ "$command" == "$executable" || "$command" == "$executable "* ]]; then
      /bin/kill "$pid" 2>/dev/null || true
    fi
  done < <(/usr/bin/pgrep -x hotspot-proxy-toggle-menu 2>/dev/null || true)
}

/bin/launchctl bootout "gui/$(/usr/bin/id -u)" "$PLIST_PATH" >/dev/null 2>&1 || true
/bin/launchctl bootout "gui/$(/usr/bin/id -u)" "$HELPER_PLIST_PATH" >/dev/null 2>&1 || true
/bin/launchctl bootout "gui/$(/usr/bin/id -u)" "$MENU_BAR_PLIST_PATH" >/dev/null 2>&1 || true
/bin/rm -f "$PLIST_PATH"
/bin/rm -f "$HELPER_PLIST_PATH"
/bin/rm -f "$MENU_BAR_PLIST_PATH"
/bin/rm -f "$BIN_LINK"
stop_app_process_at_path "$APP_INSTALL_PATH"
stop_app_process_at_path "$LEGACY_APP_INSTALL_PATH"
/bin/rm -rf "$APP_INSTALL_PATH"
/bin/rm -rf "$LEGACY_APP_INSTALL_PATH"
/bin/rm -rf "$INSTALL_ROOT"

printf 'Uninstalled %s\n' "$LABEL"
printf 'Config kept: %s\n' "$CONFIG_PATH"
