# tools.jig.nvim.md

## Scope
WP-08 provides shell invocation wrappers, terminal UX integration, and external tool/provider messaging.

## Execution Model
Jig executes external commands through `lua/jig/tools/system.lua`.

Operational rules:
- argv-first execution (`vim.system(argv, ...)`)
- no implicit `shell=true`
- explicit timeout required for sync waits (`wait(timeout_ms)`)
- deterministic metadata on every result:
  - `argv`
  - `cwd`
  - `duration_ms`
  - `timeout_ms`
  - `reason`
  - `hint`

Default working directory is resolved from Jig root policy (`jig.nav.root`) unless overridden per call.

## Failure Handling
Jig classifies non-success outcomes into explicit reasons:
- `spawn_error`
- `timeout`
- `system_wait_nil`
- `system_wait_error`
- `exit_nonzero`

If `wait()` returns nil, Jig emits a synthetic non-fatal result with `reason=system_wait_nil` and actionable remediation text.

## Capture Concurrency Guard
Async capture operations are bounded by default.
- default capture concurrency: `1`
- higher capture concurrency requires explicit opt-in

This reduces risk from parallel capture instability while keeping deterministic behavior in defaults.

## Terminal UX
Command: `:JigTerm [root|buffer]`
- default scope: `root`
- optional scope: `buffer` (current buffer directory)
- mode visibility: terminal chrome shows shell kind and live mode
- command-state feedback: running/exited status is surfaced in terminal chrome and notifications

## Tool + Provider Detection
Jig tracks shell/tool/provider status without startup auto-install.

Tool registry includes:
- required: `git`, `rg`, `fd` (`fdfind` accepted)
- recommended: `stylua`, `luacheck`
- optional: `shellcheck`

Providers checked:
- clipboard
- python3
- nodejs
- ruby

Health output provides:
- what failed
- why it failed
- next step with installation examples

## Commands
- `:JigExec {cmd...}`
- `:JigToolHealth`
- `:JigTerm [root|buffer]`

All commands are disabled in `NVIM_APPNAME=jig-safe`.

## Non-Goals and Guarantees
- Jig does not auto-install tools.
- Jig does not trigger startup network side effects.
- Missing tool/provider states are non-fatal; affected commands degrade with diagnostics.

## Verification
```bash
nvim --headless -u ./init.lua '+checkhealth jig' '+qa'
tests/tools/run_harness.sh
NVIM_APPNAME=jig-safe nvim --headless -u ./init.lua '+lua assert(vim.fn.exists(":JigExec")==0)' '+qa'
```
