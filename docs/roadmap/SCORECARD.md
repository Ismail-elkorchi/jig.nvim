# SCORECARD

Generated deterministically from committed WP-15 artifacts.

Inputs:
- `data/wp15/baselines.yaml`
- `data/wp15/evidence.jsonl`
- `data/wp15/error_budgets.json`
- `data/wp15/test_snapshot_summary.json`
- `data/wp15/agent_workflow_tasks.yaml`
- `data/wp15/gaps.yaml`
- `data/wp15/issues_snapshot.json`

Issue snapshot retrieved at: `2026-02-25T04:31:41Z`
Test summary retrieved at: `2026-02-25T04:31:41Z`

## Baseline set (pinned)

| ID | Name | Category | Pinned version | Qualitative only | Evidence items |
|---|---|---|---|---:|---:|
| `B-AG-001` | Codex CLI | `agent_cli` | `16ca527c80ea3d863be5dcac64ba37b1f8c97e47` | no | 3 |
| `B-AG-002` | Claude Code | `agent_cli` | `a0128f4a40952ce80cc7f5aba54334a74020a758` | no | 3 |
| `B-AG-003` | Gemini CLI | `agent_cli` | `bf278ef2b0e0b602983866893267d086fc429fae` | no | 3 |
| `B-AG-004` | aider | `agent_cli` | `7afaa26f8b8b7b56146f0674d2a67e795b616b7c` | no | 3 |
| `B-AG-005` | OpenCode | `agent_cli` | `a487f11a30981f44896ac771f7ade87fba9d6092` | no | 3 |
| `B-AG-006` | Continue | `agent_editor` | `98c99d3a63624ea4cea5590730b746cb9fa4dea5` | no | 3 |
| `B-AG-007` | Model Context Protocol | `agent_protocol` | `6147dff41300556b412302f0a31310491c2b7382` | no | 3 |
| `B-NV-001` | LazyVim | `nvim_distro` | `c64a61734fc9d45470a72603395c02137802bc6f` | no | 3 |
| `B-NV-002` | AstroNvim | `nvim_distro` | `7fd58328e2bc91d5cad606ee48fdf924fca6ea3e` | no | 3 |
| `B-NV-003` | NvChad | `nvim_distro` | `f437558f23c8f50c36cd09748121ab2c822e8ec9` | no | 3 |
| `B-NV-004` | LunarVim | `nvim_distro` | `aa51c20f3404cb482e9c6fd6e5e4a4bf5b1612aa` | no | 3 |
| `B-NV-005` | kickstart.nvim | `nvim_starter` | `e79572c9e6978787af2bca164a85ab6821caeb7b` | no | 3 |
| `B-NV-006` | NormalNvim | `nvim_distro` | `181dbe2114e2e49226f667bbc9b1c6d84ea0f0e1` | no | 3 |
| `B-NV-007` | LazyVim starter template | `nvim_starter` | `803bc181d7c0d6d5eeba9274d9be49b287294d99` | no | 3 |

## Universal Spec conformance

- Jig contract registry validation: **pass**
- Startup smoke (default profile): **pass**
- Startup evidence source: `startup-suite-smoke`
- Baseline conformance is qualitative-only from evidence register; no numeric baseline score is claimed.

## Reliability metrics

- Crash-free startup rate: `100.00%` (target `99.00%`) -> **pass** (sample size: `1`)

### Regression escape rate per lane

| Lane | Target | Observed | Sample | Status |
|---|---:|---:|---:|---|
| `compat-matrix` | `2.00%` | `n/a` | `0` | insufficient-data |
| `nightly-report` | `10.00%` | `n/a` | `0` | insufficient-data |
| `required` | `0.00%` | `n/a` | `0` | insufficient-data |

- Boundary: issue snapshot currently has no lane labels; regression escape rate is tracked as insufficient data.

### P95 latency budgets

| Surface | Probe | Observed ms | Budget ms | Status |
|---|---|---:|---:|---|
| navigation | `JigFiles` | `35` | `1600` | pass |
| navigation | `JigSymbols` | `30` | `1800` | pass |
| navigation | `JigDiagnostics` | `21` | `1600` | pass |
| agent_ui | `mcp_list` | `n/a` | `n/a` | pending (WP-17) |
| agent_ui | `mcp_tools` | `n/a` | `n/a` | pending (WP-17) |
| agent_ui | `policy_ask_roundtrip` | `n/a` | `n/a` | pending (WP-17) |

## Discoverability metrics

- Command-to-doc cross-reference gate: **pass**
- Keymap docs sync gate: **pass**
- Help entrypoint health (`:help jig`): **pass**

## Security controls

- Startup network trace clean: **pass**
- MCP trust enforcement: **pass**
- Exec safety override logging: **pass**

## Platform consistency

- Platform harness summary: **pass**
- WSL remains best-effort in hosted CI per WP-11 constraints.

## Agent workflow comparative gates

| Task ID | Status | Blocking WP | Oracle |
|---|---|---|---|
| `AGT-001` | `pending` | `WP-17` | `pending:agent:patch-diff-hunk-apply` |
| `AGT-002` | `implemented` | `` | `suite:security case:exec-safety-override-logging; suite:agent case:permission-policy-unit` |
| `AGT-003` | `pending` | `WP-17` | `pending:agent:approval-notification-visible` |
| `AGT-004` | `implemented` | `` | `suite:agent case:context-ledger-token-budget` |

## Gap register summary

| Gap | Severity | Surface | Owner | Status | Test plan |
|---|---|---|---|---|---|
| `GAP-001` | `sev1` | `agent` | `Ismail-elkorchi` | `open` | Implement multi-file and hunk-level apply/reject tests; falsifier: agent write path bypasses review artifact. |
| `GAP-002` | `sev1` | `agent` | `Ismail-elkorchi` | `open` | Ship queue indicator and queue list tests; falsifier: pending approval can block workflow without visible signal. |
| `GAP-003` | `sev1` | `security` | `Ismail-elkorchi` | `open` | Add failure-injection suite for workspace escape, injection payloads, and consent confusion; falsifier: simulated escape succeeds without explicit allow. |
| `GAP-004` | `sev1` | `integration` | `Ismail-elkorchi` | `open` | Implement toolchain install/update/restore/rollback probes with version equality checks; falsifier: restore cannot reproduce pinned tool versions. |
| `GAP-005` | `sev2` | `ops` | `Ismail-elkorchi` | `in_progress` | Apply severity/failure-surface labels to triaged issues and enforce label completeness on incidents. |
| `GAP-006` | `sev3` | `cmdline` | `Ismail-elkorchi` | `done` | Keep cmdline open/close stability check in required lane; falsifier: ':' path regresses due optional overlay defaults. |
| `GAP-007` | `sev3` | `startup` | `Ismail-elkorchi` | `done` | Keep startup side-effect smoke check required; falsifier: cold startup clones/fetches dependencies. |

Unresolved high-severity gaps (`sev0/sev1` and not done): **4**
- `GAP-001` -> owner `Ismail-elkorchi`, issue: https://github.com/Ismail-elkorchi/jig.nvim/issues/21
- `GAP-002` -> owner `Ismail-elkorchi`, issue: https://github.com/Ismail-elkorchi/jig.nvim/issues/21
- `GAP-003` -> owner `Ismail-elkorchi`, issue: https://github.com/Ismail-elkorchi/jig.nvim/issues/22
- `GAP-004` -> owner `Ismail-elkorchi`, issue: https://github.com/Ismail-elkorchi/jig.nvim/issues/20

## Explicit non-adoption rationale

- `GAP-006`: Non-adoption rationale: risk to baseline cmdline stability is higher than UX gain.
- `GAP-007`: Non-adoption rationale: hidden mutation at startup violates determinism contract.

## Boundaries

- Quantitative baseline comparisons are limited to pinned, reproducible artifacts.
- Baselines marked `qualitative_only` are excluded from numeric scoring.
- Agent transactional edit workflow remains pending until WP-17; current scorecard reports this as open high-severity gaps.

