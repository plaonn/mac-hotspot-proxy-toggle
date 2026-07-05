#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(/usr/bin/dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

cd "$ROOT_DIR"

scripts=(
  "bin/hotspot-proxy-toggle"
  "install.sh"
  "uninstall.sh"
  "tests/run.sh"
  "tests/install.sh"
  "scripts/validate.sh"
  "scripts/build-helper.sh"
  "scripts/build-menu-bar.sh"
  "scripts/release.sh"
)

printf '==> bash syntax\n'
bash -n "${scripts[@]}"

printf '\n==> decision tests\n'
./tests/run.sh

printf '\n==> install flow tests\n'
./tests/install.sh

if command -v shellcheck >/dev/null 2>&1; then
  printf '\n==> shellcheck\n'
  shellcheck "${scripts[@]}"
else
  printf '\n==> shellcheck\n'
  printf 'skipped: shellcheck not found\n'
fi

if command -v swiftc >/dev/null 2>&1; then
  printf '\n==> helper build\n'
  ./scripts/build-helper.sh >/dev/null
else
  printf '\n==> helper build\n'
  printf 'skipped: swiftc not found\n'
fi

if command -v swiftc >/dev/null 2>&1 && [[ -d /System/Library/Frameworks/AppKit.framework ]]; then
  printf '\n==> menu bar build\n'
  ./scripts/build-menu-bar.sh >/dev/null
else
  printf '\n==> menu bar build\n'
  printf 'skipped: swiftc or AppKit not found\n'
fi
