#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(/usr/bin/dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
TEST_TMP="${TMPDIR:-/tmp}/hotspot-proxy-toggle-notification-tests.$$"
trap '/bin/rm -rf "$TEST_TMP"' EXIT

/bin/mkdir -p "$TEST_TMP"
/usr/bin/swiftc \
  "$ROOT_DIR/Sources/NotificationPresentation.swift" \
  "$ROOT_DIR/tests/notification-presentation.swift" \
  -framework UserNotifications \
  -o "$TEST_TMP/notification-presentation-test"

"$TEST_TMP/notification-presentation-test"
