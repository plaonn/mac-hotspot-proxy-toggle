#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd -P)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
swiftc -suppress-warnings -D MENU_UI_TEST \
  "$root"/Sources/{RetryActivity,NotificationPresentation}.swift \
  "$root/Sources/hotspot-proxy-toggle-menu/main.swift" \
  "$1" "$root/tests/menu-ui.swift" -o "$fixture/test"
"$fixture/test" "$fixture"
