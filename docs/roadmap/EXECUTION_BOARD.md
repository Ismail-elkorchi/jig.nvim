# EXECUTION_BOARD

Generated from: `projects/nvim-workbench/plans/neovim-2026/roadmap.nvim-workbench.dev/dependency.roadmap.nvim-workbench.dev.v1.md`
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
- Status: `in-progress`
- Depends on: `WP-04`
- Issue: https://github.com/Ismail-elkorchi/jig.nvim/issues/9
- PR(s): tbd
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
- Status: `not-started`
- Depends on: `WP-05`
- Issue: https://github.com/Ismail-elkorchi/jig.nvim/issues/10
- PR(s): tbd
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
