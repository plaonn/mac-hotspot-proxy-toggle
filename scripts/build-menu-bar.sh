#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(/usr/bin/dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/.build}"
OUTPUT="$BUILD_DIR/hotspot-proxy-toggle-menu"

if ! command -v swiftc >/dev/null 2>&1; then
  printf 'swiftc not found; cannot build menu bar companion\n' >&2
  exit 127
fi

if [[ ! -d /System/Library/Frameworks/AppKit.framework ]]; then
  printf 'AppKit framework not found; cannot build menu bar companion\n' >&2
  exit 127
fi

/bin/mkdir -p "$BUILD_DIR"

swiftc \
  -suppress-warnings \
  "$ROOT_DIR/Sources/hotspot-proxy-toggle-menu/main.swift" \
  -framework AppKit \
  -o "$OUTPUT"

printf '%s\n' "$OUTPUT"
