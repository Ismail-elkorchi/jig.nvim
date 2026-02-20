# install.jig.nvim.md

## Clean install
```bash
mv ~/.config/nvim ~/.config/nvim.bak.$(date +%s) 2>/dev/null || true
git clone https://github.com/Ismail-elkorchi/jig.nvim ~/.config/nvim
nvim
```

## Existing config coexistence
```bash
git clone https://github.com/Ismail-elkorchi/jig.nvim ~/.config/jig
NVIM_APPNAME=jig nvim
NVIM_APPNAME=jig-safe nvim
```
