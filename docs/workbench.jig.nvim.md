# workbench.jig.nvim.md

Canonical help: `:help jig-workbench`

## Scope
Workbench Mode adds one explicit command-first session assembler for daily dogfooding:
- `:JigWorkbench [dev|review|agent|minimal]`
- `:JigWorkbenchReset`
- `:JigWorkbenchHelp`
  - opens `:help jig-workbench`; if help tags are unavailable in current runtime path, falls back to `:JigDocs`.

Default startup behavior remains unchanged:
- no startup auto-install/update
- no startup implicit network mutation
- no `jig-safe` optional-layer exposure

## Research Log (Explore phase)
- Date: 2026-02-27
- Primary roadmap source: https://neovim.io/roadmap/
- Adjacent workflow baselines:
  - Helix docs and architecture pages: https://helix-editor.com/
  - Kakoune design notes: https://github.com/mawww/kakoune/wiki/Why-Kakoune
  - tmux workflow primitives: https://github.com/tmux/tmux/wiki and https://github.com/tmux/tmux/wiki/Getting-Started
- Optional local-model ecosystem references (non-blocking, no required CI gates):
  - Ollama OpenAI compatibility: https://docs.ollama.com/openai
  - Claude Code gateway controls: https://docs.anthropic.com/en/docs/claude-code/llm-gateway
  - Codex provider configuration and local endpoint constraints:
    - https://raw.githubusercontent.com/openai/codex/main/codex-rs/core/src/config.rs
    - https://raw.githubusercontent.com/openai/codex/main/codex-rs/core/src/model_provider_info.rs
    - https://github.com/openai/codex/issues/1734
    - https://github.com/openai/codex/issues/7152

## Top 5 Daily Loops

### Loop 1: Coding (feature implementation)
Step-by-step flow:
1. Run `:JigWorkbench dev`.
2. Use left navigation pane to pick working files.
3. Edit in center pane.
4. Run local shell/test command in bottom terminal.
5. Jump diagnostics/navigation with `:JigDiagnostics` and `:JigSymbols`.

### Loop 2: Review (diff/change scan)
Step-by-step flow:
1. Run `:JigWorkbench review`.
2. Inspect left git-change surface.
3. Open changed files in center pane.
4. Run targeted validation commands in terminal.
5. Record repro/support data with `:JigVersion`.

### Loop 3: Run tests and terminal tasks
Step-by-step flow:
1. Run `:JigWorkbench dev` or `:JigWorkbench minimal`.
2. Keep center pane on failing file/test.
3. Run test/lint commands in terminal pane (when present).
4. Reset workbench with `:JigWorkbenchReset` when window state drifts.

### Loop 4: Incident triage and recovery
Step-by-step flow:
1. Run `:JigWorkbench minimal`.
2. Use deterministic docs path: `:JigWorkbenchHelp`, `:JigRepro`, `:JigHealth`.
3. Switch to `NVIM_APPNAME=jig-safe` if optional layers are suspect.
4. Collect support bundle (`:JigVersion`, `:checkhealth jig`) before issue filing.

### Loop 5: Agent-assisted patch review
Step-by-step flow:
1. Enable agent module explicitly (`vim.g.jig_agent = { enabled = true }`).
2. Run `:JigWorkbench agent`.
3. Use right queue panel to inspect pending approvals/session counts.
4. Use explicit review commands (`:JigAgentApprovals`, `:JigPatchSessions`, `:JigPatchReview`).
5. Keep edits transactional; no direct write bypass.

## Loop-to-Layout Mapping
| Loop | Minimum components |
|---|---|
| 1 | left navigation + center main + bottom terminal |
| 2 | left git-change navigation + center main + bottom terminal |
| 3 | center main + optional terminal (preset dependent) |
| 4 | center main + deterministic command/docs surfaces |
| 5 | left navigation + center main + bottom terminal + right approvals panel (agent enabled only) |

## Component Assembly and Headless Oracles
| Component | Jig assembly (primitives) | Headless oracle |
|---|---|---|
| Navigation pane | `jig.nav.root` + `jig.nav.fallback` + workbench scratch window | one `jig_workbench_role=nav` window; buffer lines include `:JigFiles`/`:JigGitChanges` |
| Main editing pane | existing active window retained as `main` role | one `jig_workbench_role=main` window remains valid |
| Terminal pane | `jig.tools.terminal.open({ scope = \"root\" })` | one `jig_workbench_role=term` window when preset requires terminal |
| Agent queue pane | `jig.agent.approvals` + `jig.agent.patch` report lines | one `jig_workbench_role=agent` window only in agent preset with agent enabled |
| Preset/idempotence state | `vim.g.jig_workbench_last` structured table | role counts stable across repeated `:JigWorkbench` invocation |

## Disconfirming Constraints and Mitigations
- Constraint: forced split re-layout can interrupt a running terminal workflow.
  - Mitigation: keep reset explicit (`:JigWorkbenchReset`), keep presets small, and preserve center window buffer.
- Constraint: users may interpret workbench as “automatic IDE intelligence” and miss explicit safety boundaries.
  - Mitigation: keep all actions command-first and observable; no hidden network/task startup.
- Constraint: agent preset can feel incomplete when agent module is disabled.
  - Mitigation: agent preset degrades explicitly (no right panel) with visible message and deterministic command hints.

## First 10 Minutes (Dogfooding Path)
1. Open project and run `:JigWorkbench dev`.
2. Edit code in center pane, navigate with left pane.
3. Execute a local command in bottom pane (`tests/run_harness.lua` subset or project tests).
4. Run `:JigWorkbench review` before commit.
5. If agent module is explicitly enabled, run `:JigWorkbench agent` for queue/patch review.
6. If state drifts, run `:JigWorkbenchReset` and re-run preset.

## Non-Goals
- No startup automation of package/tool installs.
- No mandatory UI overlay for cmdline.
- No required LLM or premium API integration.

## Verification
```bash
nvim --headless -u NONE -l scripts/workbench/check_research_done.lua
tests/workbench/run_harness.sh
NVIM_APPNAME=jig-safe nvim --headless -u ./init.lua '+lua assert(vim.fn.exists(":JigWorkbench")==0)' '+qa'
```
