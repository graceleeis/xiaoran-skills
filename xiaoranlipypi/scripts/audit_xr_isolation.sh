#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: audit_xr_isolation.sh [--upstream <ref>] [--allow-regex <regex>] [--warn-only]

Checks whether branch-only files and overlap files with upstream stay in xr-prefixed paths.

Options:
  --upstream <ref>      Upstream reference to compare against (default: origin/main)
  --allow-regex <regex> Extra allowed path regex for unavoidable shared files (default: '^$')
  --warn-only           Print warnings but exit 0
  -h, --help            Show this help message
USAGE
}

upstream="origin/main"
allow_regex="^$"
warn_only=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --upstream)
      [[ $# -ge 2 ]] || { echo "Missing value for --upstream" >&2; exit 2; }
      upstream="$2"
      shift 2
      ;;
    --allow-regex)
      [[ $# -ge 2 ]] || { echo "Missing value for --allow-regex" >&2; exit 2; }
      allow_regex="$2"
      shift 2
      ;;
    --warn-only)
      warn_only=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Not inside a git repository." >&2
  exit 2
fi

if ! git rev-parse --verify "$upstream" >/dev/null 2>&1; then
  echo "Upstream ref not found: $upstream" >&2
  echo "Run: git fetch origin --prune" >&2
  exit 2
fi

is_allowed_path() {
  local path="$1"
  local base
  base="$(basename "$path")"

  if [[ "$base" == xr* ]]; then
    return 0
  fi

  if [[ -n "$allow_regex" ]] && [[ "$path" =~ $allow_regex ]]; then
    return 0
  fi

  return 1
}

base_ref="$(git merge-base HEAD "$upstream")"

tmp_ours="$(mktemp)"
tmp_upstream="$(mktemp)"
tmp_overlap="$(mktemp)"
cleanup() {
  rm -f "$tmp_ours" "$tmp_upstream" "$tmp_overlap"
}
trap cleanup EXIT

git diff --name-only "$base_ref..HEAD" | sed '/^$/d' | sort -u > "$tmp_ours"
git diff --name-only "$base_ref..$upstream" | sed '/^$/d' | sort -u > "$tmp_upstream"
comm -12 "$tmp_ours" "$tmp_upstream" > "$tmp_overlap"

branch_violations=()
overlap_violations=()

while IFS= read -r file; do
  [[ -z "$file" ]] && continue
  if ! is_allowed_path "$file"; then
    branch_violations+=("$file")
  fi
done < <(git diff --name-only "$upstream..HEAD")

while IFS= read -r file; do
  [[ -z "$file" ]] && continue
  if ! is_allowed_path "$file"; then
    overlap_violations+=("$file")
  fi
done < "$tmp_overlap"

if [[ ${#branch_violations[@]} -eq 0 && ${#overlap_violations[@]} -eq 0 ]]; then
  echo "XR isolation audit passed."
  echo "Upstream: $upstream"
  exit 0
fi

echo "XR isolation audit found issues."
echo "Upstream: $upstream"

echo
if [[ ${#branch_violations[@]} -gt 0 ]]; then
  echo "Branch-only files not matching xr policy:"
  printf '  - %s\n' "${branch_violations[@]}"
else
  echo "Branch-only files not matching xr policy: none"
fi

echo
if [[ ${#overlap_violations[@]} -gt 0 ]]; then
  echo "Files changed on both branch and upstream (conflict risk):"
  printf '  - %s\n' "${overlap_violations[@]}"
else
  echo "Files changed on both branch and upstream: none"
fi

if [[ "$warn_only" -eq 1 ]]; then
  echo
  echo "warn-only mode enabled; exiting with 0."
  exit 0
fi

exit 1
