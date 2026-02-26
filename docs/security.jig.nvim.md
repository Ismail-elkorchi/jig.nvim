# security.jig.nvim.md

Canonical help: `:help jig-security`

## Scope
- WP-10 adds trust-boundary controls for startup networking, local-config surfaces, MCP trust policy, and destructive execution safety.
- WP-18 adds a deterministic agent threat model + regression suite for tool-using workflows.

## Security Posture
- secure by default
- explicit, user-controlled escape hatches
- no startup implicit networking
- no vendor account/API lock-in by default
- containment over absolute prevention; all high-risk decisions require attribution and audit trails

## WP-18 Threat Model (Operational)
Threat model artifacts (committed, offline):
- `data/wp18/threat_model.json`
- `data/wp18/evidence.jsonl`
- `data/wp18/fixtures_manifest.json`

Threat classes covered by WP-18:
1. workspace boundary escape (path traversal/root confusion/symlink escape)
2. argument injection patterns (`shell/git/tool argv`)
3. consent/identity confusion (approval actor/tool mismatch)
4. prompt-injection driven tool misuse
5. hidden/bidi unicode payloads in patches/diffs

Enforcement points:
- pre-tool-call gate: `lua/jig/security/gate.lua`
- patch pipeline gate: `lua/jig/agent/patch.lua`
- workspace root resolution/policy: `jig.nav.root`
- post-tool-call audit logging: `jig.agent.log`

Audit events:
- `security_pre_tool_call`
- `security_post_tool_call`

## Startup Network Policy
Jig applies startup network controls in two layers:
1. Enforcement for Jig-controlled execution paths (`jig.tools.system`, MCP start/call capability checks).
2. Optional startup trace hooks for `vim.system` and `vim.fn.system` when enabled:
   - `JIG_TRACE_STARTUP_NET=1`
   - `JIG_STRICT_STARTUP_NET=1`

Behavior:
- network-ish startup actions are denied by default unless explicitly allowlisted.
- strict mode blocks startup network-ish attempts and records trace events.
- non-strict trace mode records events without forcing a block.

Trace output:
- default path: `stdpath("state")/jig/security/startup-net-trace.jsonl`
- override path: `JIG_STARTUP_NET_TRACE_PATH`

## Local Config Execution Risks
Relevant Neovim surfaces:
- `:h 'exrc'`
- `:h 'secure'`
- `:h 'modeline'`

Risk class:
- local/project files can influence runtime behavior, including command execution surfaces depending on user settings.

Jig defaults:
- Jig does not auto-enable `exrc`.
- `:checkhealth jig` reports current `exrc`, `secure`, and `modeline` values with actionable guidance.

Recommended workflow when enabling local configs:
1. Enable only for trusted repositories.
2. Prefer `secure` when using `exrc`.
3. Disable `modeline` for stricter local-file behavior.
4. Keep `jig-safe` for minimal-surface recovery sessions.

## MCP Trust Policy
Project MCP configs (`.mcp.json`, `mcp.json`) are treated as untrusted by default.

Trust registry:
- stored in Jig state dir (`mcp_trust.json`)
- keyed by stable server id derived from command/args/cwd/source
- tracks source labels (`project-config`, `user-config`, `builtin`, `unknown`)
- stores declared capabilities per server/tool (`read/write/net/shell/git`, destructive marker)

Commands:
- `:JigMcpTrust`
- `:JigMcpTrust allow <server>`
- `:JigMcpTrust ask <server>`
- `:JigMcpTrust deny <server>`
- `:JigMcpTrust revoke <server>`

Enforcement:
- `:JigMcpStart` requires trust decision allow.
- `:JigMcpCall` blocks undeclared high-risk tool capabilities by default.

## Execution Safety Policy
`JigExec` uses conservative destructive-command classification.

Defaults:
- destructive commands are blocked unless explicit user override is provided.
- non-user actors cannot use destructive overrides.

Override path:
- user-only via `:JigExec! ...`
- override is visible in command output and written to audit/evidence log.

## Audit Logging and Retention
Jig records policy/trust/override events in append-only evidence logs.

Retention:
- size-based rotation (`max_file_bytes`, `max_files`)
- configurable under `vim.g.jig_agent.logging`

## Safe Profile Boundary
`NVIM_APPNAME=jig-safe`:
- does not load agent or MCP/ACP modules
- does not expose `:JigExec`, `:JigTerm`, `:JigMcpTrust`, or related optional command surfaces

## Boundaries and Non-Guarantees
- Jig does not claim perfect prevention for all prompt-injection variants.
- Jig cannot prove remote MCP server integrity; local policy can only deny/ask/allow with attribution.
- Human approvals can still be wrong; WP-18 focuses on visibility, scoping, and reproducible failure injection.

## Verification
```bash
tests/security/run_harness.sh
nvim --headless -u ./init.lua '+checkhealth jig' '+qa'
NVIM_APPNAME=jig-safe nvim --headless -u ./init.lua '+lua assert(vim.fn.exists(":JigMcpTrust")==0)' '+qa'
nvim --headless -u NONE -l tests/run_harness.lua -- --suite security
```
