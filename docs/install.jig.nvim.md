# install.jig.nvim.md

Canonical help: `:help jig-install`

## Clean install
```bash
mv ~/.config/nvim ~/.config/nvim.bak.$(date +%s) 2>/dev/null || true
git clone https://github.com/Ismail-elkorchi/jig.nvim ~/.config/nvim
nvim
```

After first startup, install plugin manager explicitly:
```vim
:JigPluginBootstrap
```

## Existing config coexistence
```bash
git clone https://github.com/Ismail-elkorchi/jig.nvim ~/.config/jig
NVIM_APPNAME=jig nvim
NVIM_APPNAME=jig-safe nvim
```

`jig-safe` loads only mandatory core modules for recovery/debugging.

## Channel selection (stable vs edge)
Jig supports explicit operational channels:
- `stable` (default): release-tag oriented maintenance.
- `edge`: main-branch tracking for early validation.

Choose git ref explicitly:
```bash
# stable: pin to a release tag
cd ~/.config/nvim
git fetch --tags
git checkout vX.Y.Z

# edge: track main
git checkout main
git pull --ff-only
```

Set Jig channel metadata (persisted):
```vim
:JigChannel stable
:JigChannel edge
:JigChannel
```

Optional UI profile tuning:
```vim
:JigUiProfile high-contrast
:JigIconMode ascii
```
