#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(/usr/bin/dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/.build}"
APP_PATH="${APP_PATH:-$BUILD_DIR/MHP.app}"
CONTENTS_DIR="$APP_PATH/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

if [[ ! -d /System/Library/Frameworks/AppKit.framework ]]; then
  printf 'AppKit framework not found; cannot build MHP.app\n' >&2
  exit 127
fi

/bin/rm -rf "$APP_PATH"
/bin/mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

BUILD_DIR="$MACOS_DIR" "$ROOT_DIR/scripts/build-menu-bar.sh" >/dev/null
/bin/cp "$ROOT_DIR/app/MHP-Info.plist.in" "$CONTENTS_DIR/Info.plist"

printf '%s\n' "$APP_PATH"
