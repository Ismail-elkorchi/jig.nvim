# WP-12 Delta (Issue #16)

## Already Done Before WP-12 Branch
- Stable + previous-stable CI coverage exists in required lanes.
- Nightly CI lane exists and is non-blocking.
- Unified headless harness entrypoint exists: `tests/run_harness.lua`.
- Existing suites already cover startup smoke, cmdline open/close, icon fallback, keymap conflicts, provider health, MCP failure basics, timeout/recovery basics.
- Cross-platform compatibility matrix from WP-11 is already wired in CI.

## Missing and Implemented in WP-12 Branch
- Quarantine policy and enforcement for timing-sensitive tests.
- Pending-test scaffolding and allowlist enforcement for WP-17-dependent tests.
- Dedicated completion-fallback suite.
- Deterministic perf probes beyond startup:
  - first diagnostic
  - first completion fallback confirmation
  - first picker results across small/medium/large fixture tiers
- Deterministic large-repo fixture generator (script + module; no bulk committed fixtures).
- Hidden/bidirectional Unicode CI gate.
- CI artifact publication for perf snapshots.
- Documentation for running/maintaining the test fabric.
