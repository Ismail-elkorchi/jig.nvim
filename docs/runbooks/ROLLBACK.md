# ROLLBACK.md

Scope: deterministic rollback path for user panic and maintainer incident response.

## If you are panicking: do these 3 steps
1. Open safe profile:
   ```bash
   NVIM_APPNAME=jig-safe nvim
   ```
2. Restore previous lockfile backup:
   ```vim
   :JigPluginRollback
   ```
3. Verify boot and health:
   ```bash
   nvim --headless -u ./init.lua '+qa'
   nvim --headless -u ./init.lua '+checkhealth jig' '+qa'
   ```

## Full rollback procedure
1. Confirm backup exists:
   - `${stdpath("state")}/jig/lazy-lock.previous.json`
2. Run:
   - `:JigPluginRollback`
3. If `lazy.nvim` is missing:
   - run `:JigPluginBootstrap`
   - restart Neovim
   - run `:Lazy restore`
4. If channel downgrade needed:
   ```vim
   :JigChannel stable
   ```
5. If git ref rollback is needed (stable users):
   ```bash
   git fetch --tags
   git checkout vX.Y.Z
   ```

## Verification drill
Run deterministic rollback drill:
```bash
tests/ops/run_harness.sh
```

## Not guaranteed / boundaries
- Rollback only restores plugin lock state managed by Jig.
- User-specific plugin config changes outside lockfile are not reverted automatically.
