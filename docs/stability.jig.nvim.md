# stability.jig.nvim.md

Canonical help: `:help jig-safety`

## Policy
- Default channel: `stable`
- Optional channel: `edge`
- Channel metadata is explicit and persistent (`${stdpath("state")}/jig/channel.json`).
- No direct pushes to `main`; pull request flow only.
- Linear history required on `main`.
- Startup policy: no implicit plugin/tool install, update, or network mutation.

## Update Rules
1. Update lockfile on feature branch.
2. Run startup smoke test on stable and nightly Neovim.
3. Validate critical paths:
   - `:` cmdline open
   - completion in insert/cmdline
   - diagnostics navigation
   - picker file search
4. Merge by PR after CI success.

## Native Dependency Fallbacks
- Completion fuzzy matching defaults to Lua implementation for compatibility.
- Icons degrade to ASCII when Nerd Font is unavailable.

## Incident Handling
1. Classify failure surface and severity (`sev0`..`sev3`) using runbook taxonomy.
2. Add reproducible steps + evidence + permanent fix reference (or `TBD`).
3. Run rollback drill if user impact is live (`tests/ops/run_harness.sh`).
4. Ship hotfix or rollback guidance.

Canonical operations:
- `docs/runbooks/INCIDENTS.md`
- `docs/runbooks/ROLLBACK.md`
