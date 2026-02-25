# INCIDENTS.md

Scope: canonical taxonomy, severity, and triage controls for Jig incidents.

## Failure surfaces
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

## Severity scale
- `sev0`: editor core unusable or data-loss/security-critical active incident.
- `sev1`: major workflow broken for common path; no reliable workaround.
- `sev2`: degraded behavior with workaround available.
- `sev3`: minor defect/documentation mismatch; low operational impact.

## Incident record requirements
Every incident report MUST include:
- failure surface
- severity
- exact reproduction steps
- expected vs actual behavior
- evidence (logs/snapshots/CI links)
- permanent fix reference (issue/PR/commit or `TBD`)

## Label plan
Canonical label manifest:
- `.github/labels.md`

Sync command (maintainers):
```bash
.github/scripts/sync_labels.sh Ismail-elkorchi/jig.nvim
```

## Triage flow
1. Classify surface + severity.
2. Reproduce using `:JigRepro` and safe profile check.
3. Attach deterministic evidence commands.
4. Decide response:
   - hotfix
   - rollback guidance
   - both
5. Link permanent fix reference.

## Not guaranteed / boundaries
- Incident process improves response quality but does not guarantee zero regression escape.
- Hosted CI can miss hardware/font/terminal-specific conditions; capture them as platform incidents.
