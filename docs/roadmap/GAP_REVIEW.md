# GAP_REVIEW

This process controls comparative drift for WP-15 artifacts.

## Scope

- `data/wp15/baselines.yaml`
- `data/wp15/evidence.jsonl`
- `data/wp15/issues_snapshot.json`
- `data/wp15/gaps.yaml`
- `docs/roadmap/SCORECARD.md`
- `docs/roadmap/REGRESSION_DASHBOARD.md`

## Loop trigger

Run the loop:

1. per release candidate, and
2. at least weekly during active roadmap execution.

## Deterministic procedure

1. Refresh issue snapshot (manual, networked):
   - `scripts/wp15/export_issues_snapshot.sh`
2. Refresh committed test summary (manual, local):
   - `scripts/wp15/export_test_summary.lua`
3. Validate research gate:
   - `scripts/wp15/check_research_done.lua`
4. Validate gap register:
   - `scripts/wp15/check_gaps.lua`
5. Regenerate scorecard and dashboard:
   - `scripts/wp15/generate_scorecard.lua`
   - `scripts/wp15/generate_dashboard.lua`
6. Run harness gate:
   - `nvim --headless -u NONE -l tests/run_harness.lua -- --suite scorecard`

## Parity vs non-adoption decision rule

For each identified baseline capability gap:

1. Create or update a `data/wp15/gaps.yaml` entry.
2. Classify risk and value:
   - if value >= risk and verification is feasible, track parity work as `open` with owner and test plan.
   - if risk > value, keep non-adoption explicit in `rationale` (include the phrase `non-adoption rationale:`).
3. Attach a falsifier test statement in `test_plan`.

## Turning gaps into execution work

A gap must become a work package item or issue when:

- severity is `sev0` or `sev1`, or
- the same `sev2` gap remains open for two consecutive review loops.

Required fields before promotion:

- `owner`
- `related_issue`
- `test_plan` with at least one falsifier condition.

## Drift controls

- Do not add a new baseline without pin metadata and minimum evidence coverage.
- Do not claim comparative advantage for baselines marked `qualitative_only: true`.
- Do not leave high-severity gaps (`sev0`/`sev1`) ownerless.
