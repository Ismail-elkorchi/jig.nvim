# contributing.nvim-2026.dev

## Workflow
1. Create a branch from `main`.
2. Open a pull request with a focused scope.
3. Pass CI (`ci.nvim-2026.dev`).
4. Keep commits linear and rebased.

## PR Requirements
- Include reproduction steps for fixes.
- Update docs when behavior changes.
- Include migration note for breaking changes.

## Compatibility Rules
- Do not introduce Neovim APIs deprecated in 0.11+.
- Prefer native APIs over plugin wrappers where practical.
