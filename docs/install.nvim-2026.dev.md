# install.nvim-2026.dev.md

## Clean install
```bash
mv ~/.config/nvim ~/.config/nvim.bak.$(date +%s) 2>/dev/null || true
git clone https://github.com/Ismail-elkorchi/nvim-2026.dev ~/.config/nvim
nvim
```

## Existing config coexistence
```bash
git clone https://github.com/Ismail-elkorchi/nvim-2026.dev ~/.config/nvim-2026
NVIM_APPNAME=nvim-2026 nvim
```
