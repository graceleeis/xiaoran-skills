---
name: main-first-xr-branch-sync
description: Use when maintaining a long-lived customization branch that must continuously absorb upstream main changes, minimize rebase conflicts, and isolate branch-only behavior into xr-prefixed files.
---

# Main-First XR Branch Sync

## Overview
Treat `main` as the source of truth and keep the customization branch as a thin overlay. Prefer adding `xr*` files over modifying shared upstream files.

## Workflow
1. Audit branch-only changes against the xr-isolation policy.
2. Fetch upstream and rebase with upstream-preferred conflict strategy.
3. Resolve remaining conflicts by keeping upstream, then re-apply customization in `xr*` files.
4. Verify branch-only diff remains isolated.

## Quick Start
```bash
./scripts/audit_xr_isolation.sh --upstream origin/main
./scripts/sync_main_first.sh --upstream origin/main
```

## Conflict Policy
During rebase, `--ours` keeps the rebased side (upstream `main` plus applied commits).

```bash
git checkout --ours -- <conflicted-file>
git add <conflicted-file>
git rebase --continue
```

Re-introduce customization via `xr*` files instead of reopening shared-file edits.

## Design Rules
- Keep branch-specific files named with `xr` prefix (example: `xr-foo.sh`, `xr_config.py`).
- Avoid editing files frequently touched by `main`.
- If a shared file must change, keep edits minimal and move most behavior to a new `xr*` file.
- Keep a short allowlist regex for unavoidable shared paths when running audit scripts.

## Resources
- `scripts/audit_xr_isolation.sh`: Detect non-`xr*` branch-only files and overlap risk with upstream.
- `scripts/sync_main_first.sh`: Fetch upstream, run isolation audit, and rebase with `-Xours`.
- `references/isolation-patterns.md`: Patterns for moving custom behavior out of shared files.
