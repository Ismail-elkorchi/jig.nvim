# RELEASE.md

Scope: maintainer operations for publishing Jig updates with deterministic checks.

## Channel policy
- `stable`: user-facing release channel mapped to git release tags (`vX.Y.Z`).
- `edge`: integration channel mapped to `main`.
- Channel metadata is explicit user state at `${stdpath("state")}/jig/channel.json`.
- Jig does not auto-switch git refs for users.

## Versioning policy
- `MAJOR`: incompatible behavior change in default commands, keymaps, module contracts, or safety posture.
- `MINOR`: backward-compatible feature additions.
- `PATCH`: backward-compatible fixes.

## Pre-release checklist (required)
1. Confirm required CI lanes green on release candidate commit:
   - `required` job (`stable`, `v0.11.2`)
   - cross-platform matrix lanes from WP-11
2. Run local deterministic checks:
   ```bash
   stylua --check --config-path .stylua.toml $(rg --files lua tests -g '*.lua')
   nvim --headless -u ./init.lua '+checkhealth jig' '+qa'
   nvim --headless -u NONE -l tests/run_harness.lua -- --all
   tests/ops/run_harness.sh
   tests/perf/run_harness.sh
   tests/check_hidden_unicode.sh
   nvim --headless -u NONE -l tests/check_quarantine.lua
   nvim --headless -u NONE -l tests/check_pending.lua
   nvim --headless -u NONE -l tests/docs/update_helptags.lua
   git diff --exit-code -- doc/tags
   ```
3. Validate docs sync:
   - `docs/commands.jig.nvim.md` and `doc/jig-commands.txt` reflect runtime command surface.
   - `docs/keymaps.jig.nvim.md` and `doc/jig-keymaps.txt` reflect keymap registry.
4. Validate performance budgets:
   - inspect `tests/perf/snapshots/latest-headless.json` for budget violations.

## Publish stable release
1. Create release tag from validated commit:
   ```bash
   git tag -a vX.Y.Z -m "jig.nvim vX.Y.Z"
   git push origin vX.Y.Z
   ```
2. Publish GitHub release notes with:
   - user-facing changes
   - migration notes
   - known issues
   - rollback link (`docs/runbooks/ROLLBACK.md`)
3. Confirm incident template + labels are up-to-date:
   - `.github/ISSUE_TEMPLATE/incident_report.yml`
   - `.github/labels.md`

## Not guaranteed / boundaries
- This runbook does not guarantee third-party plugin or user-local configuration compatibility.
- Hosted CI cannot cover every terminal/font combination; use incident workflow for uncovered regressions.
