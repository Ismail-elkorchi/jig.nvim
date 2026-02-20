# install.nvim-workbench.dev.md

## Clean install
```bash
mv ~/.config/nvim ~/.config/nvim.bak.$(date +%s) 2>/dev/null || true
git clone https://github.com/Ismail-elkorchi/nvim-workbench.dev ~/.config/nvim
nvim
```

## Existing config coexistence
```bash
git clone https://github.com/Ismail-elkorchi/nvim-workbench.dev ~/.config/nvim-workbench
NVIM_APPNAME=nvim-workbench nvim
```
