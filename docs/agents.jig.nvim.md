# agents.jig.nvim.md

Canonical help: `:help jig-agents`

## Scope
WP-17 extends the optional agent layer with:
- approval queue visibility and statusline indicator
- transactional patch/diff pipeline (hunk-level controls + rollback checkpoint)
- context ledger source management with hard budget guard
- instruction source disable/enable with audit logging

## Defaults
- Agent module is disabled by default.
- `NVIM_APPNAME=jig-safe` never loads `jig.agent.*` modules.
- Jig does not auto-start MCP servers or external agent processes on startup.
- Agent edits are candidates first; direct writes are denied outside patch pipeline.

## Enablement
Enable in trusted user config before Jig setup:

```lua
vim.g.jig_agent = {
  enabled = true,
}
```

Optional root-scoped overrides are supported via `vim.g.jig_agent.projects["/abs/project/root"] = { ... }`.
Jig does not execute untrusted local config files automatically.

## Approval UX
Policy `ask` decisions always enqueue pending approvals and update statusline/winbar indicators.

Commands:
- `:JigAgentApprovals`
- `:JigAgentApprovalResolve <approval_id> <allow|deny|allow-always|deny-always> [global|project|task] [scope_value]`

Policy persistence and revocation remain explicit via:
- `:JigAgentPolicyGrant ...`
- `:JigAgentPolicyRevoke <rule_id>`

## Transactional Edit Pipeline
Agent edits are applied only through patch sessions.

Commands:
- `:JigPatchCreate <json_patch_spec>`
- `:JigPatchSessions`
- `:JigPatchReview [session_id]`
- `:JigPatchHunkShow <session_id> <file_index> <hunk_index>`
- `:JigPatchHunkAccept <session_id> <file_index> <hunk_index>`
- `:JigPatchHunkReject <session_id> <file_index> <hunk_index>`
- `:JigPatchApplyAll [session_id]`
- `:JigPatchDiscardAll [session_id]`
- `:JigPatchApply [session_id]`
- `:JigPatchRollback [session_id]`

Hard boundary:
- direct file/buffer writes via agent path are denied and logged (`patch_pipeline_required`).

## Diff Legibility View
`JigPatchReview` shows:
- file list
- hunk line ranges
- intent + summary metadata

`JigPatchHunkShow` opens drill-down hunk view with unified diff markers.

ASCII mode support is preserved via `:JigIconMode ascii`.

## Context Ledger
Commands:
- `:JigAgentContext`
- `:JigAgentContextAdd <id> <bytes> [kind] [label]`
- `:JigAgentContextRemove <source_id>`
- `:JigAgentContextReset`

Ledger behavior:
- source provenance list (instructions, buffers, tool outputs, manual sources)
- byte/char sizes + token estimates (best-effort)
- hard budget enforcement on source additions

## Instruction Interoperability
Instruction sources are merged by precedence and can be toggled with audit logs.

Commands:
- `:JigAgentInstructions`
- `:JigAgentInstructionDisable <source_id|path>`
- `:JigAgentInstructionEnable <source_id|path>`

Supported source types include:
- `AGENTS.md`
- `CLAUDE.md`
- `GEMINI.md`
- user/global configured files

## Existing WP-09 surfaces (unchanged)
- MCP governance: `:JigMcpList`, `:JigMcpStart`, `:JigMcpStop`, `:JigMcpTools`, `:JigMcpCall`, `:JigMcpTrust`
- Task lifecycle + evidence log: `:JigAgentTaskStart`, `:JigAgentTaskCancel`, `:JigAgentTaskResume`, `:JigAgentTasks`, `:JigAgentLogTail`
- ACP hooks: `:JigAcpHandshake`, `:JigAcpPrompt`

## Verification
```bash
tests/agent/run_harness.sh
tests/agent_ui/run_harness.sh
NVIM_APPNAME=jig-safe nvim --headless -u ./init.lua '+lua assert(vim.fn.exists(":JigPatchReview")==0)' '+qa'
```
