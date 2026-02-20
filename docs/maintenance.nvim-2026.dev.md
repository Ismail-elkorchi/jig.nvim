# maintenance.nvim-2026.dev.md

## Release channels
- `stable`: pinned plugin updates after CI pass.
- `edge`: faster updates for compatibility validation.

## Update process
1. Update lockfile in branch.
2. Run startup + health smoke tests.
3. Validate cmdline (`:`), completion, diagnostics, and picker flows.
4. Merge via pull request only.

## Regression checklist
- Startup succeeds in headless mode.
- Cmdline opens without errors.
- Completion works in insert and cmdline modes.
- LSP attaches on known filetypes.
- Icons degrade to ASCII when Nerd Font missing.
