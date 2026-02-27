# index.jig.nvim.md

Canonical help: `:help jig`

Canonical in-editor entrypoint: `:help jig`

## First 15 Minutes
1. Install and isolate: [install.jig.nvim.md](install.jig.nvim.md) and `:help jig-install`
2. Verify runtime: `:checkhealth jig`, `:JigHealth`, and `:JigVersion`
3. Start one-command daily layout: `:JigWorkbench dev` and `:help jig-workbench`
4. Discover command surfaces: `:JigDocs` and `:help jig-commands`
5. Discover keymaps: `:JigKeys` and `:help jig-keymaps`

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
- Workbench: `:help jig-workbench`
- Keymaps: `:help jig-keymaps`
- Troubleshooting: `:help jig-troubleshooting`
- Migration: `:help jig-migration`
- Release operations: `:help jig-release`
- Rollback runbook: `:help jig-rollback`
- Incident operations: `:help jig-incidents`
- Safety model: `:help jig-safety`
- LSP: `:help jig-lsp`
- Tools: `:help jig-tools`
- Security: `:help jig-security`
- Platform: `:help jig-platform`
- Testing: `:help jig-testing`
- Agents (optional): `:help jig-agents`
- Workbench design notes: [workbench.jig.nvim.md](workbench.jig.nvim.md)
- Neovim roadmap alignment: [roadmap/NEOVIM_ROADMAP_ALIGNMENT.md](roadmap/NEOVIM_ROADMAP_ALIGNMENT.md)

## Maintainer runbooks
- Release checklist: [runbooks/RELEASE.md](runbooks/RELEASE.md)
- Rollback drill: [runbooks/ROLLBACK.md](runbooks/ROLLBACK.md)
- Incident taxonomy and severity: [runbooks/INCIDENTS.md](runbooks/INCIDENTS.md)
- Migration compatibility contract: [runbooks/MIGRATION_CONTRACT.md](runbooks/MIGRATION_CONTRACT.md)

## Boundaries
- This index documents default-profile behavior unless stated otherwise.
- Optional modules are not guaranteed in `jig-safe`.
- WP-13 does not add transactional agent edit pipelines (WP-17 scope).
