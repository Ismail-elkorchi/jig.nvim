# nvim-workbench.dev

A Neovim distribution for 2026+ focused on stability, explicit customization, and modern API usage.

## Guarantees
- Uses modern Neovim APIs (`vim.lsp.config`, `vim.lsp.enable`, `vim.system`, `vim.uv`).
- Stable defaults for cmdline, completion, and diagnostics.
- ASCII fallback when Nerd Font is not available.
- Separation between stable and edge update channels.

## Requirements
- Neovim >= 0.11.2 (recommended: latest 0.11.x stable)
- Git
- `ripgrep` (`rg`) for full picker/search features
- Nerd Font optional

## Install
```bash
mv ~/.config/nvim ~/.config/nvim.bak.$(date +%s) 2>/dev/null || true
git clone https://github.com/Ismail-elkorchi/nvim-workbench.dev ~/.config/nvim
nvim
```

## Health
Run:
```vim
:checkhealth nvimworkbench
```

## Documentation
- `docs/install.nvim-workbench.dev.md`
- `docs/keymaps.nvim-workbench.dev.md`
- `docs/architecture.nvim-workbench.dev.md`
- `docs/maintenance.nvim-workbench.dev.md`
- `docs/stability.nvim-workbench.dev.md`
- `docs/compatibility.nvim-workbench.dev.md`
- `docs/troubleshooting.nvim-workbench.dev.md`

## License
MIT
