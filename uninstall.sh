#!/bin/bash
set -euo pipefail

LABEL="com.github.plaonn.hotspot-proxy-toggle"
HELPER_LABEL="$LABEL.helper"
INSTALL_ROOT="${HOTSPOT_PROXY_INSTALL_ROOT:-$HOME/.local/share/hotspot-proxy-toggle}"
BIN_LINK="$HOME/.local/bin/hotspot-proxy-toggle"
CONFIG_PATH="${HOTSPOT_PROXY_CONFIG:-$HOME/.config/hotspot-proxy-toggle.conf}"
PLIST_PATH="$HOME/Library/LaunchAgents/$LABEL.plist"
HELPER_PLIST_PATH="$HOME/Library/LaunchAgents/$HELPER_LABEL.plist"

/bin/launchctl bootout "gui/$(/usr/bin/id -u)" "$PLIST_PATH" >/dev/null 2>&1 || true
/bin/launchctl bootout "gui/$(/usr/bin/id -u)" "$HELPER_PLIST_PATH" >/dev/null 2>&1 || true
/bin/rm -f "$PLIST_PATH"
/bin/rm -f "$HELPER_PLIST_PATH"
/bin/rm -f "$BIN_LINK"
/bin/rm -rf "$INSTALL_ROOT"

printf 'Uninstalled %s\n' "$LABEL"
printf 'Config kept: %s\n' "$CONFIG_PATH"
