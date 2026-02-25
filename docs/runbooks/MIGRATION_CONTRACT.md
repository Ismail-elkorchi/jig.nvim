# MIGRATION_CONTRACT.md

Scope: compatibility and deprecation contract for defaults shipped by Jig.

## Compatibility guarantees
Jig guarantees compatibility at the following surfaces unless a release note explicitly states otherwise:
- default `:Jig*` command names
- safe profile isolation (`NVIM_APPNAME=jig-safe`)
- no startup implicit install/update/network side effects
- keymap registry governance (no hidden default overrides)

## Deprecation policy
1. Mark behavior as deprecated in docs + vimdoc.
2. Provide replacement command/path.
3. Keep compatibility bridge for at least one `MINOR` release when feasible.
4. Remove deprecated behavior only in:
   - `MAJOR`, or
   - `MINOR` if security/safety requires immediate removal (must be called out in release notes).

## Required migration notes when defaults change
Any release that changes default behavior MUST include:
- what changed
- why it changed
- how to detect whether users are affected
- exact rollback path
- exact forward migration steps
- residual risks

## Verification hooks
- `:help jig-migration`
- `tests/docs/run_harness.sh` (doc/link/help consistency)
- `tests/ops/run_harness.sh` (rollback drill)

## Not guaranteed / boundaries
- User custom plugins and local overrides outside Jig defaults are not covered.
- Cross-repo tooling state is out of scope unless declared in release notes.
