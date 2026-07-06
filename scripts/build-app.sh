#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(/usr/bin/dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/.build}"
APP_PATH="${APP_PATH:-$BUILD_DIR/MHP.app}"
CONTENTS_DIR="$APP_PATH/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
VERSION_FILE="$ROOT_DIR/VERSION"

if [[ ! -d /System/Library/Frameworks/AppKit.framework ]]; then
  printf 'AppKit framework not found; cannot build MHP.app\n' >&2
  exit 127
fi

if [[ ! -x /usr/bin/swift ]]; then
  printf 'swift not found; cannot generate MHP.app icon\n' >&2
  exit 127
fi

/bin/rm -rf "$APP_PATH"
/bin/mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

APP_VERSION="$(/usr/bin/tr -d '[:space:]' <"$VERSION_FILE")"
if [[ ! "$APP_VERSION" =~ ^[0-9]+(\.[0-9]+){1,2}([._-][0-9A-Za-z.-]+)?$ ]]; then
  printf 'invalid VERSION: %s\n' "$APP_VERSION" >&2
  exit 64
fi

BUILD_DIR="$MACOS_DIR" "$ROOT_DIR/scripts/build-menu-bar.sh" >/dev/null
/usr/bin/sed \
  -e "s|__APP_VERSION__|$APP_VERSION|g" \
  "$ROOT_DIR/app/MHP-Info.plist.in" >"$CONTENTS_DIR/Info.plist"
/usr/bin/swift "$ROOT_DIR/scripts/generate-app-icon.swift" "$RESOURCES_DIR/MHP.icns" >/dev/null

printf '%s\n' "$APP_PATH"
