#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(/usr/bin/dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/.build}"
OUTPUT="$BUILD_DIR/hotspot-proxy-toggle-menu"
VERSION_FILE="$ROOT_DIR/VERSION"
GENERATED_VERSION="$BUILD_DIR/hotspot-proxy-toggle-version.swift"

if ! command -v swiftc >/dev/null 2>&1; then
  printf 'swiftc not found; cannot build menu bar companion\n' >&2
  exit 127
fi

if [[ ! -d /System/Library/Frameworks/AppKit.framework ]]; then
  printf 'AppKit framework not found; cannot build menu bar companion\n' >&2
  exit 127
fi

/bin/mkdir -p "$BUILD_DIR"

APP_VERSION="$(/usr/bin/tr -d '[:space:]' <"$VERSION_FILE")"
if [[ ! "$APP_VERSION" =~ ^[0-9]+(\.[0-9]+){1,2}([._-][0-9A-Za-z.-]+)?$ ]]; then
  printf 'invalid VERSION: %s\n' "$APP_VERSION" >&2
  exit 64
fi

{
  printf 'enum BuildInfo {\n'
  printf '    static let appName = "Mac Hotspot Proxy Toggle"\n'
  printf '    static let appVersion = "%s"\n' "$APP_VERSION"
  printf '}\n'
} >"$GENERATED_VERSION"

swiftc \
  -suppress-warnings \
  "$ROOT_DIR/Sources/hotspot-proxy-toggle-menu/main.swift" \
  "$GENERATED_VERSION" \
  -framework AppKit \
  -o "$OUTPUT"

printf '%s\n' "$OUTPUT"
