# architecture.jig.nvim.md

Canonical help: `:help jig`

## Modules
- `spec/requirements.lua`: machine-readable contract registry + self-check.
- `core/bootstrap.lua`: version gate, profile detection, safe-mode gating.
- `core/options.lua`: editor defaults, font detection, loader setup.
- `core/keymaps.lua`: keymap application + `:JigKeys` command.
- `core/keymap_registry.lua`: schema, conflict policy, safety constraints, runtime index.
- `core/keymap_panel.lua`: discoverability panel for keymap index.
- `core/keymap_docs.lua`: generated docs/vimdoc renderer + sync gate.
- `core/autocmd.lua`: diagnostics/yank UX behaviors.
- `core/doctor.lua`: health/provenance/bisect command entrypoints.
- `core/lazy.lua`: plugin bootstrap and channel command.
- `core/channel.lua`: persisted stable/edge channel state (`stdpath("state")/jig/channel.json`).
- `core/plugin_state.lua`: install/update/restore/rollback lifecycle commands.
- `core/health.lua`: health provider used by `:checkhealth jig`.
- `nav/root.lua`: deterministic root resolution policy.
- `nav/guardrails.lua`: large-repo caps and ignore policies.
- `nav/backend.lua`: picker backend bridge with fallback routing.
- `nav/fallback.lua`: builtin command-safe fallback navigation paths.
- `nav/miller.lua`: optional Miller-column mode module.
- `lsp/config.lua`: LSP defaults and policy override data.
- `lsp/registry.lua`: server registry validation and deterministic server list resolution.
- `lsp/lifecycle.lua`: isolated per-server configure/enable lifecycle.
- `lsp/diagnostics.lua`: diagnostics policy.
- `lsp/inlay_hints.lua`: inlay hints policy.
- `lsp/format_on_save.lua`: format-on-save policy.
- `lsp/snapshot.lua`: structured LSP context snapshot export.
- `lsp/health.lua`: actionable LSP health reporting.
- `lsp/init.lua`: LSP orchestration + `:JigLsp*` commands.
- `platform/os.lua`: OS class, architecture, and WSL detection.
- `platform/path.lua`: path join/normalize semantics and cross-platform helpers.
- `platform/fs.lua`: filesystem helpers and `stdpath` contract surface.
- `platform/clipboard.lua`: clipboard provider detection and non-fatal hints.
- `platform/shell.lua`: shell discovery/classification and argv one-liner strategy.
- `platform/init.lua`: aggregated platform capabilities export.
- `tools/platform.lua`: compatibility adapter delegating to `jig.platform`.
- `tools/registry.lua`: required/recommended/optional external tool registry and install hints.
- `tools/system.lua`: deterministic `vim.system` wrappers (timeouts, nil handling, capture queue).
- `tools/terminal.lua`: terminal integration with mode visibility and command-state feedback.
- `tools/toolchain.lua`: manifest+lockfile lifecycle for external toolchain install/update/restore/rollback and drift reporting.
- `tools/health.lua`: shell/provider/tool health summaries and checkhealth integration.
- `tools/init.lua`: command orchestration + `:JigExec`, `:JigToolHealth`, `:JigTerm`, and `:JigToolchain*` lifecycle commands.
- `security/config.lua`: runtime security policy defaults + override merge.
- `security/startup_phase.lua`: startup phase boundary tracking (`startup` -> `done`).
- `security/net_guard.lua`: startup network classification, deny-by-default, and trace hooks.
- `security/mcp_trust.lua`: MCP trust registry with source labels and capability enforcement.
- `security/exec_safety.lua`: destructive execution classifier + override controls.
- `security/init.lua`: security setup orchestration for default profile.
- `agent/config.lua`: optional multi-agent feature flags and trusted override merging.
- `agent/policy.lua`: allow/ask/deny engine with persistent revocable grants.
- `agent/log.lua`: append-only JSONL evidence logging.
- `agent/health.lua`: optional health summary for agent state and MCP discovery.
- `agent/task.lua`: task handles with cancel/resume and evidence continuity.
- `agent/instructions.lua`: instruction artifact discovery and precedence merge.
- `agent/observability.lua`: context ledger capture, budget warnings, and panel rendering.
- `agent/mcp/config.lua`: MCP config discovery (`.mcp.json`, `mcp.json`) and normalization.
- `agent/mcp/transport.lua`: minimal stdio JSON-RPC transport for deterministic MCP tests.
- `agent/mcp/client.lua`: MCP lifecycle/list/call orchestration with policy routing.
- `agent/backends/acp_stdio.lua`: ACP-stdio handshake/prompt skeleton for candidate outputs.
- `agent/init.lua`: optional command-first surface for `:JigMcp*`, `:JigAgent*`, and `:JigAcp*`.
- `ui/init.lua`: UI policy wiring (tokens, profiles, chrome, cmdline checks).
- `ui/tokens.lua`: semantic highlight token system.
- `ui/chrome.lua`: active/inactive statusline + winbar policy.
- `ui/float.lua`: border hierarchy, elevation model, collision policy.
- `ui/icons.lua`: Nerd Font/ASCII icon mode adapter.

## Plugin Layers
- `plugins/ui.lua`: colorscheme, icons, keymap discovery UI.
- `plugins/find.lua`: picker/navigation.
- `plugins/lsp.lua`: native LSP runtime wiring + optional Mason command surface.
- `plugins/completion.lua`: completion stack with stable fallback.
- `plugins/git.lua`: git signs and hunk state.
- `plugins/syntax.lua`: treesitter highlighting/indent.

## Test Fabric Modules
- `tests/run_harness.lua`: unified headless suite runner (`--suite <name>`).
- `tests/check_quarantine.lua`: timing-sensitive quarantine allowlist gate.
- `tests/check_pending.lua`: pending-test allowlist gate for roadmap-blocked checks.
- `lua/jig/tests/fixtures/nav_repo.lua`: deterministic tiered repository generator for nav/perf probes.
- `lua/jig/tests/perf/harness.lua`: deterministic perf probes and extreme-regression budgets.
- `lua/jig/tests/ops/harness.lua`: release/rollback/incident operations drill suite.

## Policy
- Stability-first defaults.
- Native API alignment with Neovim 0.11+.
- ASCII fallback for iconography.
- PR-only + linear-history governance on `main`.
- Optional extensions (including agent modules) must be removable without breaking core startup.
- Agent module is disabled by default and never loaded in `NVIM_APPNAME=jig-safe`.
