#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(/usr/bin/dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/.build}"
OUTPUT="$BUILD_DIR/hotspot-proxy-toggle-helper"

if ! command -v swiftc >/dev/null 2>&1; then
  printf 'swiftc not found; cannot build helper\n' >&2
  exit 127
fi

/bin/mkdir -p "$BUILD_DIR"

swiftc \
  "$ROOT_DIR/Sources/hotspot-proxy-toggle-helper/main.swift" \
  -framework SystemConfiguration \
  -o "$OUTPUT"

printf '%s\n' "$OUTPUT"
