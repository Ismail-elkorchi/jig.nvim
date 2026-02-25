# MAINTAINERS.md

## Incident Triage Categories
Use one primary failure surface per issue:
- startup
- cmdline
- completion
- lsp
- ui
- performance
- platform
- integration
- agent
- security

## Severity Scale
- sev0: unusable core or security/data-loss active incident
- sev1: major workflow failure without practical workaround
- sev2: degraded behavior with workaround
- sev3: low-impact defect/documentation mismatch

## Reproduction Workflow
1. Attempt repro on default profile.
2. Attempt repro on safe profile:
   - `NVIM_APPNAME=jig-safe nvim`
3. Request minimal repro output:
   - `:JigRepro`
4. Request environment evidence:
   - `nvim --version`
   - `:checkhealth jig`
   - `:JigHealth`
5. Record incident template fields:
   - permanent fix reference (`TBD` allowed while active)
   - severity + failure surface labels

## CI Failure Interpretation
- `check_hidden_unicode.sh`: hidden/bidi character introduced.
- `check_quarantine.lua`: timing-sensitive case not allowlisted or stale allowlist.
- `check_pending.lua`: pending test policy drift.
- `perf` suite: extreme latency regression gate hit.
- `docs` suite: docs/help/command cross-reference regression.
- `ops` suite: rollback/channel operations regression.

## Docs Drift Control
- Regenerate/check command docs via docs harness.
- Regenerate/check helptags:
  - `nvim --headless -u NONE -l tests/docs/update_helptags.lua`
  - `git diff --exit-code -- doc/tags`

## PR Acceptance Rules
Require:
- deterministic verification commands and outputs
- falsifiers explicitly checked
- residual risks listed
- docs updated for any new default command/keymap behavior

## Label Sync
Canonical manifest: `.github/labels.md`

Sync command:
```bash
.github/scripts/sync_labels.sh Ismail-elkorchi/jig.nvim
```
