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
  "tests/helper.sh"
  "tests/notification.sh"
  "tests/menu-ui.sh"
  "scripts/validate.sh"
  "scripts/build-helper.sh"
  "scripts/build-menu-bar.sh"
  "scripts/build-app.sh"
  "scripts/github-release.sh"
  "scripts/release.sh"
)

printf '==> bash syntax\n'
for script in "${scripts[@]}"; do bash -n "$script"; done

printf '\n==> decision tests\n'
./tests/run.sh
/usr/bin/ruby tests/proxy.rb

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
  helper_bin="$(./scripts/build-helper.sh)"
  /usr/bin/ruby tests/reconnect.rb "$helper_bin"
  printf '\n==> helper lifecycle tests\n'
  ./tests/helper.sh
else
  printf '\n==> helper build\n'
  printf 'skipped: swiftc not found\n'
  printf '\n==> helper lifecycle tests\n'
  printf 'skipped: swiftc not found\n'
fi

if command -v swiftc >/dev/null 2>&1 && [[ -d /System/Library/Frameworks/AppKit.framework ]]; then
  printf '\n==> menu bar build\n'
  menu_binary="$(./scripts/build-menu-bar.sh)"
  ./tests/menu-ui.sh "$(dirname "$menu_binary")/hotspot-proxy-toggle-version.swift"
  printf '\n==> notification presentation tests\n'
  ./tests/notification.sh
  printf '\n==> app bundle build\n'
  ./scripts/build-app.sh >/dev/null
else
  printf '\n==> menu bar build\n'
  printf 'skipped: swiftc or AppKit not found\n'
  printf '\n==> app bundle build\n'
  printf 'skipped: swiftc or AppKit not found\n'
fi
