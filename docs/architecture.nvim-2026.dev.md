# architecture.nvim-2026.dev.md

## Modules
- `core/options.lua`: editor defaults, font detection, loader setup.
- `core/keymaps.lua`: keymap registry (initial baseline).
- `core/autocmd.lua`: diagnostics/yank UX behaviors.
- `core/lazy.lua`: plugin bootstrap and channel command.

## Plugin Layers
- `plugins/ui.lua`: colorscheme, icons, statusline.
- `plugins/find.lua`: picker/navigation.
- `plugins/lsp.lua`: native LSP + Mason.
- `plugins/completion.lua`: completion stack with stable fallback.

## Policy
- Stability-first defaults.
- Native API alignment with Neovim 0.11+.
- ASCII fallback for iconography.
