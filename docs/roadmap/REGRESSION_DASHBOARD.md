# REGRESSION_DASHBOARD

Generated deterministically from committed artifacts.

- Source issues snapshot: `2026-02-25T04:31:41Z`

## Quarantine entries by failure surface

| Surface | Count |
|---|---:|
| `agent` | `1` |
| `cmdline` | `1` |
| `integration` | `1` |

## Pending tests by failure surface

| Surface | Count |
|---|---:|
| `agent` | `2` |

## Perf budget status

| Probe | Observed ms | Budget ms | Status |
|---|---:|---:|---|
| `time-to-first-diagnostic` | `21` | `1600` | pass |
| `time-to-first-completion-menu` | `0` | `400` | pass |
| `time-to-first-picker-small` | `14` | `800` | pass |
| `time-to-first-picker-medium` | `35` | `1600` | pass |
| `time-to-first-picker-large` | `30` | `2600` | pass |

- Summary: pass=`5`, near=`0`, fail=`0`, pending=`0`

## Open gaps by failure surface

| Surface | Open gaps |
|---|---:|
| `agent` | `2` |
| `integration` | `1` |
| `ops` | `1` |
| `security` | `1` |

## Issue labels snapshot

| Label | Count |
|---|---:|
| `none` | `0` |

## Boundaries

- Trend history is append-based: keep prior snapshots in `data/wp15/dashboard_snapshot.json` when adopting periodic updates.
- Label-driven metrics require consistent issue labeling discipline; low label density reduces interpretability.

