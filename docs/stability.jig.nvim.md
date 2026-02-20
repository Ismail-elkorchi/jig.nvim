# stability.jig.nvim.md

## Policy
- Default channel: `stable`
- Optional channel: `edge`
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
1. Classify regression surface (`startup`, `cmdline`, `completion`, `lsp`, `ui`, `platform`).
2. Add reproducible test case.
3. Ship hotfix or rollback guidance.
