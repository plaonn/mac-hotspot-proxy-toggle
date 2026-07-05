#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(/usr/bin/dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
VERSION="${1:-}"

FORMULA_NAME="hotspot-proxy-toggle"
TAP_NAME="plaonn/tap"
TAP_DIR="${HOMEBREW_TAP_DIR:-$ROOT_DIR/../homebrew-tap}"
FORMULA_REL_PATH="Formula/$FORMULA_NAME.rb"
FORMULA_PATH="$TAP_DIR/$FORMULA_REL_PATH"
RUN_HOMEBREW_CHECKS="${RUN_HOMEBREW_CHECKS:-1}"

usage() {
  cat <<'EOF'
Usage:
  scripts/release.sh v1.3.0

Environment:
  HOMEBREW_TAP_DIR       Path to the plaonn/homebrew-tap checkout.
                         Defaults to ../homebrew-tap relative to this repo.
  RUN_HOMEBREW_CHECKS    Set to 0 to skip brew audit/install/test after pushing
                         the tap update. Default: 1.
EOF
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

run_git() {
  local dir="$1"
  shift
  git -C "$dir" "$@"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

require_clean_worktree() {
  local dir="$1"
  local status

  status="$(run_git "$dir" status --porcelain)"
  [[ -z "$status" ]] || die "worktree is not clean: $dir"
}

require_main_not_behind_origin() {
  local dir="$1"
  local branch head upstream merge_base

  branch="$(run_git "$dir" rev-parse --abbrev-ref HEAD)"
  [[ "$branch" == "main" ]] || die "expected main branch in $dir, got $branch"

  run_git "$dir" fetch origin main:refs/remotes/origin/main --tags

  head="$(run_git "$dir" rev-parse HEAD)"
  upstream="$(run_git "$dir" rev-parse origin/main)"
  merge_base="$(run_git "$dir" merge-base HEAD origin/main)"

  [[ "$merge_base" == "$upstream" ]] ||
    die "$dir is behind or diverged from origin/main; merge remote changes first"

  printf '%s\n' "$head"
}

release_tarball_url() {
  printf 'https://github.com/plaonn/mac-hotspot-proxy-toggle/archive/refs/tags/%s.tar.gz' "$VERSION"
}

sha256_for_url() {
  local url="$1"
  local tmp

  tmp="$(mktemp)"
  trap 'rm -f "$tmp"' RETURN
  curl -L --fail --silent --show-error "$url" -o "$tmp"
  shasum -a 256 "$tmp" | /usr/bin/awk '{ print $1 }'
}

update_formula() {
  local url="$1"
  local sha256="$2"

  ruby - "$FORMULA_PATH" "$url" "$sha256" <<'RUBY'
formula_path, url, sha256 = ARGV
text = File.read(formula_path)

updated = text.sub(%r{url "https://github\.com/plaonn/mac-hotspot-proxy-toggle/archive/refs/tags/[^"]+\.tar\.gz"}, %(url "#{url}"))
abort "formula url not found" if updated == text

updated_sha = updated.sub(/sha256 "[0-9a-f]{64}"/, %(sha256 "#{sha256}"))
abort "formula sha256 not found" if updated_sha == updated

File.write(formula_path, updated_sha)
RUBY
}

push_source_release() {
  local head tag_commit

  head="$(require_main_not_behind_origin "$ROOT_DIR")"
  ./scripts/validate.sh
  run_git "$ROOT_DIR" push origin main

  if run_git "$ROOT_DIR" rev-parse -q --verify "refs/tags/$VERSION" >/dev/null; then
    tag_commit="$(run_git "$ROOT_DIR" rev-list -n 1 "$VERSION")"
    [[ "$tag_commit" == "$head" ]] ||
      die "tag $VERSION already exists but does not point at HEAD"
    printf 'Tag already exists at HEAD: %s\n' "$VERSION"
  else
    run_git "$ROOT_DIR" tag "$VERSION"
    printf 'Created tag: %s\n' "$VERSION"
  fi

  run_git "$ROOT_DIR" push origin "$VERSION"
}

push_tap_update() {
  local formula_version

  require_main_not_behind_origin "$TAP_DIR" >/dev/null
  require_clean_worktree "$TAP_DIR"

  update_formula "$(release_tarball_url)" "$(sha256_for_url "$(release_tarball_url)")"

  if run_git "$TAP_DIR" diff --quiet -- "$FORMULA_REL_PATH"; then
    printf 'Formula already points at %s\n' "$VERSION"
    return 0
  fi

  brew style "$FORMULA_PATH"

  formula_version="${VERSION#v}"
  run_git "$TAP_DIR" add "$FORMULA_REL_PATH"
  run_git "$TAP_DIR" commit -m "Update $FORMULA_NAME to $formula_version"
  run_git "$TAP_DIR" push origin main
}

run_homebrew_checks() {
  [[ "$RUN_HOMEBREW_CHECKS" == "1" ]] || {
    printf 'Skipped Homebrew checks because RUN_HOMEBREW_CHECKS=%s\n' "$RUN_HOMEBREW_CHECKS"
    return 0
  }

  brew tap "$TAP_NAME" >/dev/null
  run_git "$(brew --repo "$TAP_NAME")" fetch origin main:refs/remotes/origin/main
  run_git "$(brew --repo "$TAP_NAME")" checkout main
  run_git "$(brew --repo "$TAP_NAME")" reset --hard origin/main

  brew audit --formula "$TAP_NAME/$FORMULA_NAME"
  if brew list --formula "$FORMULA_NAME" >/dev/null 2>&1; then
    brew reinstall --build-from-source "$TAP_NAME/$FORMULA_NAME"
  else
    brew install --build-from-source "$TAP_NAME/$FORMULA_NAME"
  fi
  brew test "$TAP_NAME/$FORMULA_NAME"
}

main() {
  if [[ -z "$VERSION" || "$VERSION" == "-h" || "$VERSION" == "--help" ]]; then
    usage
    [[ -n "$VERSION" ]] || exit 64
    exit 0
  fi

  [[ "$VERSION" =~ ^v[0-9]+(\.[0-9]+){1,2}([._-][0-9A-Za-z.-]+)?$ ]] ||
    die "version must look like v1.2.3: $VERSION"

  [[ -f "$FORMULA_PATH" ]] || die "formula not found: $FORMULA_PATH"

  require_command curl
  require_command git
  require_command ruby
  require_command shasum
  require_command brew

  require_clean_worktree "$ROOT_DIR"
  require_clean_worktree "$TAP_DIR"

  cd "$ROOT_DIR"
  push_source_release
  push_tap_update
  run_homebrew_checks

  printf 'Released %s and updated %s/%s\n' "$VERSION" "$TAP_NAME" "$FORMULA_NAME"
}

main "$@"
