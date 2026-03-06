# Isolation Patterns

## Goal
Keep upstream files stable and place customization in `xr*` files.

## Patterns
- Use wrapper entry points: create `xr-<tool>.sh` and call the upstream script from it.
- Use sidecar config: keep branch-only settings in `xr*.toml` or `xr*.yaml` and load them conditionally.
- Use additive modules: create `xr_*.py` helpers and import them from a thin integration point.
- Keep edits in shared files minimal: prefer one hook call instead of duplicating logic.

## Migration Checklist
1. List branch-only files: `git diff --name-only origin/main..HEAD`.
2. For each shared-file edit, move branch-specific logic into a new `xr*` file.
3. Leave a tiny call site in the shared file only if required.
4. Re-run `scripts/audit_xr_isolation.sh` until only allowed paths remain.

## Allowlist Guidance
Use `--allow-regex` only for paths that cannot be avoided. Keep it short and explicit, for example:

```bash
--allow-regex '^(setup\.py|publish_to_pypi\.sh)$'
```

Review the allowlist regularly and remove entries after migration to `xr*` files.
