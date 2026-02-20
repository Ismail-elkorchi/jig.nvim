# troubleshooting.jig.nvim.md

## Run Health Check
```vim
:checkhealth jig
```

## Cmdline Error On `:`
1. Start safe profile:
```bash
NVIM_APPNAME=jig-safe nvim
```
2. Cmdline completion is disabled by default for stability. Confirm:
```vim
:lua print(require('blink.cmp.config').cmdline.enabled)
```
Expected default: `false`.
3. If the error only appears in non-safe profile, inspect optional plugin overrides.

## Plugin Manager Missing
1. Confirm path:
```vim
:lua print(vim.fn.stdpath("data") .. "/lazy/lazy.nvim")
```
2. Install explicitly:
```vim
:JigPluginBootstrap
```
3. Restart Neovim and run:
```vim
:JigPluginInstall
```

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
