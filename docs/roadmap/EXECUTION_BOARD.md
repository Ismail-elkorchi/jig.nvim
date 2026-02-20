# EXECUTION_BOARD

Generated from: `dependency roadmap (internal planning source)`
Updated at: `2026-02-20`

## Status Legend
- `not-started`
- `in-progress`
- `done`
- `blocked`

## Work Packages

### WP-04: UI Foundation, Accessibility, and Visual Hierarchy
- Status: `done`
- Depends on: `WP-01`
- Issue: https://github.com/Ismail-elkorchi/jig.nvim/issues/8
- PR(s): https://github.com/Ismail-elkorchi/jig.nvim/pull/29
- ADR(s): tbd

### WP-05: Finder, Navigation, and Information Architecture
- Status: `done`
- Depends on: `WP-04`
- Issue: https://github.com/Ismail-elkorchi/jig.nvim/issues/9
- PR(s): https://github.com/Ismail-elkorchi/jig.nvim/pull/30
- ADR(s): tbd
- Deliverables (excerpt):
  - deterministic root resolution policy (`vim.fs.root` + markers)
  - command-first navigation primitives (`:JigFiles`, `:JigBuffers`, `:JigRecent`, `:JigSymbols`, `:JigDiagnostics`, `:JigHistory`, `:JigGitChanges`)
  - optional Miller-column mode
  - large-repo guardrails (caps + ignore policy + bounded candidate lists)
- Verification commands (excerpt):
  - `tests/nav/run_harness.sh`
  - `nvim --headless -u ./init.lua '+lua assert(vim.fn.exists(":JigFiles")==2)' '+qa'`
- Falsifiers (excerpt):
  - root detection diverges for equivalent marker sets
  - candidate list length exceeds configured cap under large-list path

### WP-06: Keymap Registry and Discoverability
- Status: `done`
- Depends on: `WP-05`
- Issue: https://github.com/Ismail-elkorchi/jig.nvim/issues/10
- PR(s): https://github.com/Ismail-elkorchi/jig.nvim/pull/31
- ADR(s): tbd
- Deliverables (excerpt):
  - declarative keymap registry schema
  - conflict detector and CI gate
  - generated keymap docs and vimdoc sync gate
- Verification commands (excerpt):
  - keymap schema/conflict tests
  - docs generation diff gate
- Falsifiers (excerpt):
  - runtime keymaps diverge from registry output
  - undocumented default mappings exist

### WP-07: LSP, Diagnostics, and Language Runtime
- Status: `done`
- Depends on: `WP-01`
- Issue: https://github.com/Ismail-elkorchi/jig.nvim/issues/11
- PR(s): https://github.com/Ismail-elkorchi/jig.nvim/pull/32
- ADR(s): tbd
- Deliverables (excerpt):
  - modern LSP APIs (`vim.lsp.config`, `vim.lsp.enable`)
  - policy-separated modules (lifecycle, diagnostics, inlay hints, format-on-save)
  - deprecation gate against `deprecated.txt`
  - command-first observability (`:JigLspHealth`, `:JigLspInfo`, `:JigLspSnapshot`)
- Verification commands (excerpt):
  - `tests/lsp/run_harness.sh`
  - `tests/lsp/check_deprecated.sh`
  - `nvim --headless -u ./init.lua '+checkhealth jig' '+qa'`
  - `NVIM_APPNAME=jig-safe nvim --headless -u ./init.lua '+lua assert(vim.fn.exists(":JigLspInfo")==0)' '+qa'`
- Falsifiers (excerpt):
  - deprecated APIs used in maintained LSP modules
  - single server failure breaks global initialization

### WP-08: Completion and Command UX
- Status: `not-started`
- Depends on: `WP-07`
- Issue: tbd
- PR(s): tbd
- ADR(s): tbd
