#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(/usr/bin/dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
VERSION="${1:-}"
REPOSITORY="${GITHUB_REPOSITORY:-plaonn/mac-hotspot-proxy-toggle}"

usage() {
  cat <<'EOF'
Usage:
  scripts/github-release.sh v1.3.0

Creates the GitHub Release for an existing release tag if it does not already
exist. Release notes are generated from the commits since the previous version
tag and include English/Korean sections.

Environment:
  GITHUB_REPOSITORY  Repository owner/name. Defaults to plaonn/mac-hotspot-proxy-toggle.
  GH_TOKEN           Token used by gh to create or read the release.
EOF
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

previous_version_tag() {
  git tag --sort=version:refname |
    /usr/bin/awk -v version="$VERSION" '$0 == version { print previous; exit } { previous = $0 }'
}

write_release_notes() {
  local notes_path="$1"
  local previous_tag compare_url range

  previous_tag="$(previous_version_tag)"
  if [[ -n "$previous_tag" ]]; then
    range="$previous_tag..$VERSION"
    compare_url="https://github.com/${REPOSITORY}/compare/${previous_tag}...${VERSION}"
  else
    range="$VERSION"
    compare_url=""
  fi

  {
    printf '## English\n\n'
    printf '### What'\''s Changed\n\n'
    if git log --format='- %s (%h)' --reverse "$range" | grep .; then
      :
    else
      printf -- '- Release %s.\n' "$VERSION"
    fi
    if [[ -n "$compare_url" ]]; then
      printf '\n### Compare\n\n'
      printf -- '- %s\n' "$compare_url"
    fi
    printf '\n### Validation\n\n'
    printf -- '- ./scripts/validate.sh\n'
    printf -- '- GitHub Release exists for %s\n' "$VERSION"
    printf -- '- Homebrew tap Formula points at %s\n' "$VERSION"

    printf '\n## 한국어\n\n'
    printf '### 변경 사항\n\n'
    if git log --format='- %s (%h)' --reverse "$range" | grep .; then
      :
    else
      printf -- '- %s 릴리스입니다.\n' "$VERSION"
    fi
    if [[ -n "$compare_url" ]]; then
      printf '\n### 비교\n\n'
      printf -- '- %s\n' "$compare_url"
    fi
    printf '\n### 검증\n\n'
    printf -- '- ./scripts/validate.sh\n'
    printf -- '- %s GitHub Release 존재\n' "$VERSION"
    printf -- '- Homebrew tap Formula %s 반영\n' "$VERSION"
  } >"$notes_path"
}

main() {
  if [[ -z "$VERSION" || "$VERSION" == "-h" || "$VERSION" == "--help" ]]; then
    usage
    [[ -n "$VERSION" ]] || exit 64
    exit 0
  fi

  [[ "$VERSION" =~ ^v[0-9]+(\.[0-9]+){1,2}([._-][0-9A-Za-z.-]+)?$ ]] ||
    die "version must look like v1.2.3: $VERSION"

  require_command git
  require_command gh

  cd "$ROOT_DIR"

  git rev-parse -q --verify "refs/tags/$VERSION" >/dev/null ||
    die "tag not found locally: $VERSION"

  if gh api -X GET "repos/${REPOSITORY}/releases/tags/${VERSION}" >/dev/null 2>&1; then
    printf 'GitHub Release already exists: %s\n' "$VERSION"
    return 0
  fi

  notes_path="$(mktemp)"
  trap 'rm -f "$notes_path"' EXIT
  write_release_notes "$notes_path"

  gh release create "$VERSION" \
    --repo "$REPOSITORY" \
    --title "$VERSION" \
    --notes-file "$notes_path" \
    --verify-tag
}

main "$@"
