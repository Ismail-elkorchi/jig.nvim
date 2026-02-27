# NEOVIM_ROADMAP_ALIGNMENT.md

Reference roadmap: https://neovim.io/roadmap/

## Scope
This note defines how Jig aligns with upstream Neovim roadmap changes without forcing premature migrations.

## Roadmap items affecting Jig
1. `vim.pack` (Neovim 0.12 package-management surface)
2. `vim.async` (Neovim 0.13 async/task primitives)
3. UI/event evolution (cmdline/ext-message/event surfaces and related API refinements)

## Adopt later
- `vim.pack`: evaluate as optional backend after parity tests confirm lockfile/install/rollback guarantees remain deterministic.
- `vim.async`: evaluate for internal task orchestration only after cancellation/error semantics match current safety gates.
- UI/event additions: adopt only when cmdline stability can be proven with existing harness checks.

## Abstract now
- Keep plugin lifecycle behind Jig command surface (`:JigPlugin*`) and state files rather than hard-coding one backend assumption.
- Keep command execution behind `jig.tools.system` wrapper so async substrate can change without user-facing behavior drift.
- Keep workbench orchestration behind `jig.workbench` module with explicit role/state metadata for deterministic testing.

## Intentionally not chasing
- No roadmap-item adoption solely for trend alignment.
- No migration that weakens startup invariants (`no auto-install`, `no startup network mutation`).
- No mandatory UI overlays that bypass native cmdline path.

## Falsifiable compatibility checks
- If backend migration is introduced, existing restore/rollback tests must pass unchanged.
- If async substrate migration is introduced, timeout/cancellation/failure-isolation tests must remain deterministic.
- If UI primitives change, cmdline open/close and workbench harnesses must remain green in required lanes.
