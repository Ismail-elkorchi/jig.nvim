# agents.jig.nvim.md

Canonical help: `:help jig-agents`

## Scope
WP-09 adds an optional multi-agent interoperability layer with policy routing, MCP governance, ACP bridge hooks, and auditable task lifecycle controls.

## Defaults
- Agent module is disabled by default.
- `NVIM_APPNAME=jig-safe` never loads `jig.agent.*` modules.
- Jig does not auto-start MCP servers or external agent processes on startup.

## Enablement
Enable in trusted user config before Jig setup:

```lua
vim.g.jig_agent = {
  enabled = true,
}
```

Optional root-scoped overrides are supported via `vim.g.jig_agent.projects["/abs/project/root"] = { ... }`.
Jig does not execute untrusted local config files automatically.

## Policy Model
All tool actions use allow/ask/deny routing through `lua/jig/agent/policy.lua`.

Defaults:
- `read`: `allow`
- `write|net|git|shell|unknown`: `ask`

Persistence:
- explicit grants/revokes are stored in Jig state dir (`policy.json`)
- revocation is explicit and auditable

Commands:
- `:JigAgentPolicyList`
- `:JigAgentPolicyGrant <allow|ask|deny> <tool> <action_class> <target> <scope> [scope_value]`
- `:JigAgentPolicyRevoke <rule_id>`

## MCP Governance
Config discovery precedence:
1. `.mcp.json`
2. `mcp.json`

Commands:
- `:JigMcpList`
- `:JigMcpStart <server>`
- `:JigMcpStop <server>|all`
- `:JigMcpTools <server>`
- `:JigMcpCall <server> <tool> <json_args>`
- `:JigMcpTrust`
- `:JigMcpTrust allow|ask|deny|revoke <server>`

Trust notes:
- discovered server sources are labeled (`project-config`, `user-config`, `builtin`, `unknown`)
- project MCP configs are treated as untrusted by default (`ask`)
- capability declarations are enforced per server/tool

Failure classes are non-fatal and explicit:
- missing binary
- early exit
- timeout/no response
- malformed JSON-RPC response
- tool not found

## Task Lifecycle and Evidence
Task handles are Jig-level metadata handles, not model-state replay.

Commands:
- `:JigAgentTaskStart [title]`
- `:JigAgentTaskCancel <task_id>`
- `:JigAgentTaskResume <task_id>`
- `:JigAgentTasks`
- `:JigAgentLogTail [count]`

Evidence log:
- append-only JSONL in Jig state dir (`events.jsonl`)
- records timestamp, session id, task id, request, policy decision, and result summary

## Instruction Interoperability + Context Ledger
Instruction files are text-ingested only (never executed):
- `AGENTS.md`
- `CLAUDE.md`
- `GEMINI.md`
- additional user/global paths via config

Commands:
- `:JigAgentInstructions`
- `:JigAgentContext`
- `:JigAgentContextReset`

Context ledger provides source listing + byte/char estimates + budget warnings.
Token counts are best-effort and only shown when supplied by backend metadata.

## ACP Bridge Hooks
`lua/jig/agent/backends/acp_stdio.lua` provides a minimal ACP-stdio handshake/prompt skeleton for candidate outputs.

Commands:
- `:JigAcpHandshake <json_spec>`
- `:JigAcpPrompt <json_spec> <prompt>`

## Explicit Boundary
WP-09 does **not** apply edits to files or buffers.
Agent outputs are candidates only. Transactional patch/diff application is deferred to WP-17.

## Verification
```bash
tests/agent/run_harness.sh
nvim --headless -u ./init.lua '+lua assert(vim.fn.exists(":JigMcpList")==0)' '+qa'
NVIM_APPNAME=jig-safe nvim --headless -u ./init.lua '+lua assert(vim.fn.exists(":JigMcpList")==0)' '+qa'
```
