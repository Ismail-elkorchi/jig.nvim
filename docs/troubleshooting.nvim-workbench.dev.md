# troubleshooting.nvim-workbench.dev.md

## Run Health Check
```vim
:checkhealth nvimworkbench
```

## Cmdline Error On `:`
1. Start Neovim without third-party local overrides.
2. Validate completion fallback:
```vim
:lua print(require('blink.cmp.config').fuzzy.implementation)
```
Expected default: `lua`.

## Icon Rendering Problems
1. Verify Nerd Font is installed in terminal profile.
2. If missing, distro falls back to ASCII icons automatically.
3. Validate detection:
```vim
:lua print(vim.g.have_nerd_font)
```

## LSP Not Attaching
1. Confirm server availability:
```vim
:checkhealth vim.lsp
```
2. Confirm config enabled:
```vim
:lua print(vim.inspect(vim.lsp.is_enabled('lua_ls')))
```

## Picker/Search Not Working
1. Confirm `rg` is installed:
```bash
rg --version
```
2. Reopen Neovim and retry `<leader><leader>` and `<leader>/`.
