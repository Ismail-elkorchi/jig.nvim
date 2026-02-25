# maintenance.jig.nvim.md

Canonical help: `:help jig-migration`
Primary runbooks:
- `docs/runbooks/RELEASE.md`
- `docs/runbooks/ROLLBACK.md`
- `docs/runbooks/INCIDENTS.md`
- `docs/runbooks/MIGRATION_CONTRACT.md`

## Release channels
- `stable`: release-tag oriented updates after required CI lanes pass.
- `edge`: main-branch tracking for compatibility validation.
- Channel persistence path: `${stdpath("state")}/jig/channel.json`.
- Startup side-effect policy: do not auto-install or auto-update plugins/toolchains.

## Update process
1. Ensure plugin manager exists (`:JigPluginBootstrap` if missing).
2. Run `:JigPluginUpdate` and confirm apply explicitly.
3. Validate startup + health smoke tests.
4. Validate cmdline (`:`), completion, diagnostics, and picker flows.
5. Commit lockfile changes in branch.
6. Merge via pull request only.

## Plugin lifecycle commands
- Install/sync: `:JigPluginInstall`
- Update (transactional confirm): `:JigPluginUpdate`
- Restore from lockfile: `:JigPluginRestore`
- Roll back using previous lockfile backup: `:JigPluginRollback`

## Regression checklist
- Startup succeeds in headless mode.
- Cmdline opens without errors.
- Completion works in insert and cmdline modes.
- LSP attaches on known filetypes.
- Icons degrade to ASCII when Nerd Font missing.
- Keymap docs/vimdoc are synchronized with registry (`tests/keymaps/run_harness.sh`).
- Run release drill suite (`tests/ops/run_harness.sh`) before release tagging.
