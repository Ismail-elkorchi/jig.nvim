# plugin-manager.jig.nvim.md

Canonical help: `:help jig`

## Backend Compatibility
- Primary backend: `lazy.nvim`.
- Fallback strategy: if `lazy.nvim` is absent, startup remains functional and provides explicit bootstrap command:
  - `:JigPluginBootstrap`

## Lock and Restore Policy
- Lockfile path: `lazy-lock.json` under config root.
- Rollback backup path: `${stdpath("state")}/jig/lazy-lock.previous.json`.
- Channel metadata path: `${stdpath("state")}/jig/channel.json`.
- Startup policy: no implicit install/update/network mutation.

## Commands
- `:JigPluginInstall`
  - sync/install plugins from the current spec/lock state.
- `:JigPluginUpdate`
  - runs `Lazy check`, requires explicit confirm, then applies update.
  - saves a rollback backup when lockfile exists.
- `:JigPluginRestore`
  - restores plugins from `lazy-lock.json`.
- `:JigPluginRollback`
  - restores backup lockfile regardless of `lazy.nvim` availability.
  - runs `Lazy restore` only when `lazy.nvim` is available.
  - if `lazy.nvim` is absent, prints deterministic next steps.

## Rollback Path
1. Run `:JigPluginRollback`.
2. If `lazy.nvim` is missing, run `:JigPluginBootstrap`, restart Neovim, then `:Lazy restore`.
3. Verify startup:
```bash
nvim --headless -u ./init.lua '+qa'
```
4. Run health:
```vim
:checkhealth jig
```
