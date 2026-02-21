# testing.jig.nvim.md

Canonical help: `:help jig-testing`

## Scope
WP-12 defines Jig test fabric contracts for determinism, failure injection, and CI gating.

## Local Commands
- Run all default suites:
  - `nvim --headless -u NONE -l tests/run_harness.lua -- --all`
- Run one suite:
  - `nvim --headless -u NONE -l tests/run_harness.lua -- --suite ui`
- Run perf probes:
  - `tests/perf/run_harness.sh`
- Validate timing-sensitive quarantine policy:
  - `nvim --headless -u NONE -l tests/check_quarantine.lua`
- Validate pending-test allowlist policy:
  - `nvim --headless -u NONE -l tests/check_pending.lua`
- Validate hidden/bidi Unicode gate:
  - `tests/check_hidden_unicode.sh`

## Snapshot Contract
Each suite writes `tests/<suite>/snapshots/latest-headless.json` with:
- `harness`: suite contract identifier
- `cases`: per-case status/details/labels
- `summary`: pass/fail and pending aggregates

Timing-sensitive cases MUST include:
- `labels: ["timing-sensitive"]`
- deterministic retry policy (`attempts`, fixed retry count, fixed delay)

## Quarantine Policy
- Allowlist file: `tests/quarantine.json`
- CI fails if:
  - a timing-sensitive case appears without allowlist entry
  - an allowlist entry is stale
- If allowlist grows in a PR, PR body MUST include `[quarantine-justification]`.

## Pending Test Policy
- Allowlist file: `tests/pending_tests.json`
- Pending tests are limited to roadmap dependencies not implemented yet.
- CI fails if:
  - a pending case is not allowlisted
  - allowlisted pending entries are stale

Current pending set tracks WP-17-dependent surfaces:
- approval visibility UI for pending actions
- transactional patch/diff hunk accept/reject pipeline

## Performance Probes
Perf suite: `lua/jig/tests/perf/harness.lua`
- `time-to-first-diagnostic`
- `time-to-first-completion-menu` (headless fallback confirmation path)
- `time-to-first-picker-results` across deterministic fixture tiers

Budgets: `tests/perf/budgets.json`
- thresholds are conservative and serve as extreme-regression gates
- output snapshots are uploaded as CI artifacts

## Deterministic Large-Repo Fixture
Generator module: `lua/jig/tests/fixtures/nav_repo.lua`
Generator script: `tests/fixtures/generate_nav_fixture.lua`
- creates tiered fixture repos (`small`, `medium`, `large`)
- no bulk generated file trees are committed

## Adding a New Suite Safely
1. Add suite module under `lua/jig/tests/<suite>/harness.lua`.
2. Register suite in `tests/run_harness.lua`.
3. Add snapshot directory + `.gitignore`.
4. Add CI step with deterministic assertions.
5. If timing-sensitive, add retry labels and quarantine entry.
6. If dependency-blocked, add pending case + allowlist entry.
