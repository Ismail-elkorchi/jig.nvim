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
- Startup does not auto-install plugins. Use `:JigPluginBootstrap` explicitly when needed.

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

## Commands
- `:JigPluginBootstrap` install `lazy.nvim` explicitly.
- `:JigChannel stable|edge` set update channel metadata.

## Profiles
- `NVIM_APPNAME=jig` uses the default profile.
- `NVIM_APPNAME=jig-safe` loads only mandatory core modules.

## Verification
```bash
pattern='(nvim[-_]workbench|nvim(workbench)|nvim[-]2026|nvim(2026)|[N]vimWorkbench|[D]istroHealth|:[D]istro|distro[-]safe|distro[.])'
rg -n "$pattern" . && exit 1 || true
lua -e 'package.path="./lua/?.lua;./lua/?/init.lua;"..package.path; assert(require("jig.spec.requirements").self_check())'
rg -n "MUST|SHOULD|MAY" docs/contract.jig.nvim.md
nvim --headless -u ./init.lua '+lua print("jig-smoke")' '+qa'
nvim --headless -u ./init.lua '+lua assert(vim.g.jig_profile=="default")' '+qa'
NVIM_APPNAME=jig-safe nvim --headless -u ./init.lua '+lua assert(vim.g.jig_profile=="safe")' '+qa'
nvim --headless -u ./init.lua '+checkhealth jig' '+qa'
```

## Documentation
- `docs/install.jig.nvim.md`
- `docs/contract.jig.nvim.md`
- `docs/keymaps.jig.nvim.md`
- `docs/architecture.jig.nvim.md`
- `docs/maintenance.jig.nvim.md`
- `docs/stability.jig.nvim.md`
- `docs/compatibility.jig.nvim.md`
- `docs/troubleshooting.jig.nvim.md`

## License
MIT
