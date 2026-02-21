# index.jig.nvim.md

Canonical help: `:help jig`

Canonical in-editor entrypoint: `:help jig`

## First 15 Minutes
1. Install and isolate: [install.jig.nvim.md](install.jig.nvim.md) and `:help jig-install`
2. Verify runtime: `:checkhealth jig` and `:JigHealth`
3. Discover commands: `:JigDocs` and `:help jig-commands`
4. Discover keymaps: `:JigKeys` and `:help jig-keymaps`

## If Something Breaks
1. Open safe profile: `NVIM_APPNAME=jig-safe nvim`
2. Read failure-class guide: [troubleshooting.jig.nvim.md](troubleshooting.jig.nvim.md) and `:help jig-troubleshooting`
3. Print minimal repro workflow: `:JigRepro`
4. Run deterministic harness subset: `nvim --headless -u NONE -l tests/run_harness.lua -- --suite docs --suite startup`

## Topic Index
- Overview: `:help jig`
- Install: `:help jig-install`
- Configuration: `:help jig-configuration`
- Commands: `:help jig-commands`
- Keymaps: `:help jig-keymaps`
- Troubleshooting: `:help jig-troubleshooting`
- Migration: `:help jig-migration`
- Safety model: `:help jig-safety`
- LSP: `:help jig-lsp`
- Tools: `:help jig-tools`
- Security: `:help jig-security`
- Platform: `:help jig-platform`
- Testing: `:help jig-testing`
- Agents (optional): `:help jig-agents`

## Boundaries
- This index documents default-profile behavior unless stated otherwise.
- Optional modules are not guaranteed in `jig-safe`.
- WP-13 does not add transactional agent edit pipelines (WP-17 scope).
