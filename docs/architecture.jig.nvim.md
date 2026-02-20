# architecture.jig.nvim.md

## Modules
- `spec/requirements.lua`: machine-readable contract registry + self-check.
- `core/bootstrap.lua`: version gate, profile detection, safe-mode gating.
- `core/options.lua`: editor defaults, font detection, loader setup.
- `core/keymaps.lua`: keymap registry (initial baseline).
- `core/autocmd.lua`: diagnostics/yank UX behaviors.
- `core/lazy.lua`: plugin bootstrap and channel command.
- `core/plugin_state.lua`: install/update/restore/rollback lifecycle commands.
- `core/health.lua`: health provider used by `:checkhealth jig`.

## Plugin Layers
- `plugins/ui.lua`: colorscheme, icons, statusline.
- `plugins/find.lua`: picker/navigation.
- `plugins/lsp.lua`: native LSP + Mason.
- `plugins/completion.lua`: completion stack with stable fallback.
- `plugins/git.lua`: git signs and hunk state.
- `plugins/syntax.lua`: treesitter highlighting/indent.

## Policy
- Stability-first defaults.
- Native API alignment with Neovim 0.11+.
- ASCII fallback for iconography.
- PR-only + linear-history governance on `main`.
- Optional extensions (including agent modules) must be removable without breaking core startup.
