# maintenance.jig.nvim.md

## Release channels
- `stable`: pinned plugin updates after CI pass.
- `edge`: faster updates for compatibility validation.
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
