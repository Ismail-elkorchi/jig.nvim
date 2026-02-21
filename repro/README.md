# repro README

Use this template to produce deterministic bug reports.

## Run Minimal Repro
```bash
nvim --clean -u repro/minimal_init.lua
```

## Isolated Environment (recommended)
```bash
XDG_CONFIG_HOME=$(mktemp -d) \
XDG_DATA_HOME=$(mktemp -d) \
XDG_STATE_HOME=$(mktemp -d) \
XDG_CACHE_HOME=$(mktemp -d) \
NVIM_APPNAME=jig-repro \
nvim --clean -u repro/minimal_init.lua
```

## Collect Evidence
```bash
nvim --version
nvim --headless -u ./init.lua '+checkhealth jig' '+qa'
nvim --headless -u ./init.lua '+JigHealth' '+qa'
```

## If Startup Fails
```bash
NVIM_APPNAME=jig-safe nvim
nvim --startuptime /tmp/jig.startuptime.log -u ./init.lua '+qa'
```
