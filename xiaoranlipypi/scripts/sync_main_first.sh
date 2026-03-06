#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: sync_main_first.sh [--upstream <ref>] [--allow-regex <regex>] [--skip-audit]

Sync current branch from upstream main while preferring upstream content on conflict.

Options:
  --upstream <ref>      Upstream reference to rebase onto (default: origin/main)
  --allow-regex <regex> Extra allowed path regex passed to audit script (default: '^$')
  --skip-audit          Skip xr isolation audit
  -h, --help            Show this help message
USAGE
}

upstream="origin/main"
allow_regex="^$"
skip_audit=0

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
    --skip-audit)
      skip_audit=1
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

branch_name="$(git symbolic-ref --quiet --short HEAD || true)"
if [[ -z "$branch_name" ]]; then
  echo "Detached HEAD is not supported for branch sync." >&2
  exit 2
fi

if [[ "$branch_name" == "main" || "$branch_name" == "master" ]]; then
  echo "Refusing to run on $branch_name. Checkout your customization branch first." >&2
  exit 2
fi

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "Working tree is not clean. Commit or stash changes first." >&2
  exit 2
fi

remote_name="origin"
if [[ "$upstream" == */* ]]; then
  remote_name="${upstream%%/*}"
fi

git fetch "$remote_name" --prune

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ "$skip_audit" -eq 0 ]]; then
  "$script_dir/audit_xr_isolation.sh" --upstream "$upstream" --allow-regex "$allow_regex"
fi

echo "Rebasing $branch_name onto $upstream with -Xours ..."
if git rebase -Xours "$upstream"; then
  echo "Rebase completed. Branch-only files versus $upstream:"
  git diff --name-only "$upstream..HEAD" | sed 's/^/  - /'
  exit 0
fi

echo "Rebase stopped due to conflicts." >&2
echo "To prefer upstream on remaining files during rebase:" >&2
echo "  git checkout --ours -- <file>" >&2
echo "  git add <file>" >&2
echo "  git rebase --continue" >&2
exit 1
