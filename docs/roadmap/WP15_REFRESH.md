# WP15_REFRESH

Operational runbook for refreshing WP-15 offline comparative artifacts.

## Scope

- Refreshes only `data/wp15/*` snapshot artifacts and generated roadmap outputs.
- Keeps CI deterministic and offline during evaluation lanes.

## Refresh trigger

Run this protocol when one of the following is true:

- `scripts/wp15/check_research_done.lua` reports stale snapshot/evidence inputs.
- A release cycle requires an updated WP-15 evidence snapshot.
- Issue/test snapshots were updated and scorecard artifacts must be regenerated.

## Snapshot-date protocol

1) Refresh source snapshots first.  
2) Re-verify evidence entries touched in this cycle and update their `retrieved_at`.  
3) Update `data/wp15/snapshot_meta.yaml.snapshot_date` to the refresh date.  
4) Regenerate outputs and run gates.

> Warning: changing `snapshot_date` without refreshing evidence/snapshot inputs is invalid and must fail gates.

## Commands

```bash
# 1) Refresh issue snapshot (manual network step, not run in CI)
scripts/wp15/export_issues_snapshot.sh

# 2) Refresh test summary snapshot from committed harness artifacts
nvim --headless -u NONE -l scripts/wp15/export_test_summary.lua

# 3) Update evidence entries that were re-verified
#    (edit data/wp15/evidence.jsonl retrieved_at fields for touched items only)

# 4) Regenerate scorecard + dashboard outputs
scripts/wp15/generate_scorecard.lua
scripts/wp15/generate_dashboard.lua

# 5) Run WP-15 gates
scripts/wp15/check_research_done.lua
scripts/wp15/check_gaps.lua
nvim --headless -u NONE -l tests/run_harness.lua -- --suite scorecard
tests/check_hidden_unicode.sh
```

## Completion criteria

- WP-15 gates pass locally with no stale-input violations.
- Generated outputs are synchronized with committed artifacts.
- PR body includes verification command output summaries.
