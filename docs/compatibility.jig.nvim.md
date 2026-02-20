# compatibility.jig.nvim.md

## Neovim Support
- Minimum: `0.11.2`
- Recommended: latest `0.11.x` stable
- Nightly: supported in CI as compatibility signal, not as default runtime target.
- Version gate: startup fails fast with deterministic error text below `0.11.2`.

## Platform Targets
- Linux: x86_64, arm64
- macOS: x86_64, arm64
- Windows: native + WSL

## Runtime Expectations
- `git` required
- `ripgrep` recommended for search pickers
- Nerd Font optional (ASCII fallback enabled)
- truecolor preferred for default theme quality
- Native `:` cmdline remains default (no mandatory cmdline overlay).

## API Baseline
- `vim.lsp.config` / `vim.lsp.enable`
- `vim.system`
- `vim.uv`
- `vim.fs.root`
- `vim.diagnostic.jump`

## Known Compatibility Constraints
- Systems without toolchains/native binaries should still run completion due Lua fuzzy fallback.
- When clipboard provider is missing, editor remains functional but clipboard integration is degraded.
- `NVIM_APPNAME=jig-safe` disables optional plugin layers for recovery workflows.
- UI icon mode can be forced via `:JigIconMode ascii` on terminals without Nerd Fonts.
