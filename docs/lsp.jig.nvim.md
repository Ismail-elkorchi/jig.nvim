# lsp.jig.nvim.md

Canonical help: `:help jig-lsp`

## Scope
WP-07 provides Jig's LSP runtime boundary with explicit policy modules and failure isolation.

## APIs
Jig uses modern Neovim LSP APIs:
- `vim.lsp.config`
- `vim.lsp.enable`

Deprecated APIs are blocked by CI via `tests/lsp/check_deprecated.sh`.

## Module Boundaries
- `lua/jig/lsp/config.lua`: default policy data + user overrides (`vim.g.jig_lsp`).
- `lua/jig/lsp/registry.lua`: server registry validation and deterministic entry resolution.
- `lua/jig/lsp/lifecycle.lua`: per-server configure/enable flow with isolation.
- `lua/jig/lsp/diagnostics.lua`: diagnostics policy.
- `lua/jig/lsp/inlay_hints.lua`: inlay hints policy.
- `lua/jig/lsp/format_on_save.lua`: format-on-save policy.
- `lua/jig/lsp/snapshot.lua`: structured context snapshot for observability and future agent workflows.
- `lua/jig/lsp/health.lua`: actionable health reporting.
- `lua/jig/lsp/init.lua`: command registration + policy orchestration.

## Commands
- `:JigLspHealth`
- `:JigLspInfo`
- `:JigLspSnapshot [path]`

These commands are available only in default profile. They are absent in `NVIM_APPNAME=jig-safe`.

## Failure Isolation Policy
Each server is processed independently:
1. validate server spec
2. check binary availability
3. configure via `vim.lsp.config`
4. enable via `vim.lsp.enable`

A failure in any server is recorded with remediation text and does not abort other servers.

## Safe Defaults
- no startup auto-install
- no startup auto-network side effects
- inlay hints default to disabled
- format-on-save default to disabled

## Snapshot Structure
`:JigLspSnapshot` exports a structured table/JSON including:
- profile and appname
- current buffer and diagnostics counts
- attached clients and roots
- server lifecycle state
- active policy values

## Verification
```bash
nvim --headless -u ./init.lua '+checkhealth jig' '+qa'
tests/lsp/run_harness.sh
tests/lsp/check_deprecated.sh
NVIM_APPNAME=jig-safe nvim --headless -u ./init.lua '+lua assert(vim.fn.exists(":JigLspInfo")==0)' '+qa'
```
