# migration.jig.nvim.md

Canonical help: `:help jig-migration`
Contract details: `docs/runbooks/MIGRATION_CONTRACT.md`

## Workflow
1. Backup current config.
2. Test Jig in isolated appname.
3. Validate commands/keymaps you use daily.
4. Validate fallback workflows (`jig-safe`, `:JigRepro`).
5. Move production profile after checks pass.

## Verification Commands
```bash
nvim --headless -u ./init.lua '+checkhealth jig' '+qa'
nvim --headless -u ./init.lua '+JigHealth' '+qa'
nvim --headless -u NONE -l tests/run_harness.lua -- --suite startup --suite docs
```

## Rollback
```bash
NVIM_APPNAME=jig-safe nvim
```
Then:
```vim
:JigPluginRollback
```

## Boundaries
- Migration cannot automatically reconcile unrelated user plugins/config.
- Third-party plugin behavior outside Jig defaults is not guaranteed.
- Deprecation grace windows and compatibility scope are defined in migration contract.
