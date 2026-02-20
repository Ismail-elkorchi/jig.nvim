# jig.nvim

Jig is a Neovim distribution focused on predictable defaults and explicit operations.

## Canonical IDs
- Brand: `Jig`
- Repository slug: `jig.nvim`
- `NVIM_APPNAME` default: `jig`
- `NVIM_APPNAME` safe profile: `jig-safe`
- Lua namespace root: `jig`
- User command prefix: `:Jig*`
- Autocmd groups: `Jig*`
- Highlight groups: `Jig*`
- Help prefix: `jig-*` and `:help jig`

## Requirements
- Neovim >= `0.11.2`
- `git`
- `ripgrep` (`rg`) for picker/grep paths
- Nerd Font optional (ASCII fallback supported)

## Install
```bash
mv ~/.config/nvim ~/.config/nvim.bak.$(date +%s) 2>/dev/null || true
git clone https://github.com/Ismail-elkorchi/jig.nvim ~/.config/nvim
nvim
```

## Isolated Profiles
```bash
git clone https://github.com/Ismail-elkorchi/jig.nvim ~/.config/jig
NVIM_APPNAME=jig nvim
NVIM_APPNAME=jig-safe nvim
```

## Health
```vim
:checkhealth jig
```

## Verification
```bash
pattern='(nvim[-_]workbench|nvim(workbench)|nvim[-]2026|nvim(2026)|[N]vimWorkbench|[D]istroHealth|:[D]istro|distro[-]safe|distro[.])'
rg -n "$pattern" . && exit 1 || true
nvim --headless -u ./init.lua '+lua print("jig-smoke")' '+qa'
nvim --headless -u ./init.lua '+checkhealth jig' '+qa'
```

## Documentation
- `docs/install.jig.nvim.md`
- `docs/keymaps.jig.nvim.md`
- `docs/architecture.jig.nvim.md`
- `docs/maintenance.jig.nvim.md`
- `docs/stability.jig.nvim.md`
- `docs/compatibility.jig.nvim.md`
- `docs/troubleshooting.jig.nvim.md`

## License
MIT
