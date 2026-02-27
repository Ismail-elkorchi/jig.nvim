# jig.nvim

Jig is a Neovim distribution focused on predictable defaults and explicit operations.

## Canonical IDs
- Brand: `Jig`
- Repository slug: `jig.nvim`
- `NVIM_APPNAME` default: `jig`
- `NVIM_APPNAME` safe profile: `jig-safe`
- Lua namespace root: `jig`
- User command prefix: `:Jig*`
- Autocmd groups: `Jig*`
- Highlight groups: `Jig*`
- Help prefix: `jig-*` and `:help jig`

## Requirements
- Neovim >= `0.11.2`
- `git`
- `ripgrep` (`rg`) for picker/grep paths
- Nerd Font optional (ASCII fallback supported)
- Startup does not auto-install plugins. Use `:JigPluginBootstrap` explicitly when needed.

## Install
```bash
mv ~/.config/nvim ~/.config/nvim.bak.$(date +%s) 2>/dev/null || true
git clone https://github.com/Ismail-elkorchi/jig.nvim ~/.config/nvim
nvim
```

## Isolated Profiles
```bash
git clone https://github.com/Ismail-elkorchi/jig.nvim ~/.config/jig
NVIM_APPNAME=jig nvim
NVIM_APPNAME=jig-safe nvim
```

## Health
```vim
:checkhealth jig
```

## Commands
- `:JigHealth` run distro + provider health checks.
- `:JigVersion` print deterministic support report (Jig commit, Neovim version, OS, channel, stdpaths).
- `:JigVerboseMap {lhs}` show keymap provenance.
- `:JigVerboseSet {option}` show option provenance.
- `:JigBisectGuide` print deterministic bisect guidance.
- `:JigKeys` open keymap index panel.
- `:JigUiProfile {profile}` set accessibility profile.
- `:JigIconMode {mode}` set icon mode (`auto|nerd|ascii`).
- `:JigCmdlineCheck` run native cmdline open/close check.
- `:JigFloatDemo` open sample floats with policy-driven borders/elevation/collision.
- `:JigRootSet [path]` set deterministic navigation root override.
- `:JigRootReset` clear deterministic navigation root override.
- `:JigFiles` open files navigation.
- `:JigBuffers` open buffers navigation.
- `:JigRecent` open recent-files navigation.
- `:JigSymbols` open symbols navigation.
- `:JigDiagnostics` open diagnostics navigation.
- `:JigHistory` open command-history navigation.
- `:JigGitChanges` open git-changes navigation.
- `:JigMiller` open optional Miller-column navigation mode.
- `:JigLspHealth` show LSP health with per-server remediation.
- `:JigLspInfo` show enabled servers and current buffer attach status.
- `:JigLspSnapshot [path]` print JSON snapshot or write LSP state to file.
- `:JigExec {cmd...}` run non-interactive command with deterministic result capture.
- `:JigExec! {cmd...}` user-only destructive override path (visible warning + audit log).
- `:JigToolHealth` show shell/provider/tool integration summary.
- `:JigTerm [root|buffer]` open integrated terminal in Jig root (or current buffer directory).
- `:JigWorkbench [preset]` assemble an idempotent daily-driver layout (`dev|review|agent|minimal`).
- `:JigWorkbenchReset` reset workbench role panes in the current tab.
- `:JigWorkbenchHelp` open workbench help topic.
- `:JigMcpList` list discovered MCP servers (when agent module enabled).
- `:JigMcpTrust` list MCP trust state/capabilities and update allow/ask/deny/revoke.
- `:JigMcpStart <server>` start MCP handshake for one server (when enabled).
- `:JigMcpStop <server>|all` stop MCP runtime state (when enabled).
- `:JigMcpTools <server>` list tools from server via policy-routed call (when enabled).
- `:JigMcpCall <server> <tool> <json_args>` call MCP tool through allow/ask/deny policy (when enabled).
- `:JigAgentPolicyList` list persistent policy grants.
- `:JigAgentPolicyGrant ...` persist allow/ask/deny policy rules with explicit scope.
- `:JigAgentPolicyRevoke <rule_id>` revoke persistent policy rule.
- `:JigAgentInstructions` show merged AGENTS/CLAUDE/GEMINI instruction sources.
- `:JigAgentContext` show context ledger sources and budget warnings.
- `:JigAgentTaskStart|Cancel|Resume|Tasks` manage auditable task handles.
- `:JigAcpHandshake` and `:JigAcpPrompt` run ACP-stdio bridge hooks for candidate responses.
- `:JigPluginBootstrap` install `lazy.nvim` explicitly.
- `:JigPluginInstall` sync/install plugins.
- `:JigPluginUpdate` preview (`Lazy check`) then apply update with explicit confirm.
- `:JigPluginRestore` restore plugin state from `lazy-lock.json`.
- `:JigPluginRollback` restore previous lockfile backup + `Lazy restore`.
- `:JigChannel [stable|edge]` show or set persistent update channel metadata.

## Profiles
- `NVIM_APPNAME=jig` uses the default profile.
- `NVIM_APPNAME=jig-safe` loads only mandatory core modules.
- Agent layer is disabled by default in `jig` and absent in `jig-safe`.
- Enable agent module explicitly with trusted config:
  `vim.g.jig_agent = { enabled = true }`

## Release Channels
- `stable` (default): release-tag oriented operations and conservative upgrade cadence.
- `edge`: branch-tracking operations for compatibility validation and early changes.
- Channel state persists at `${stdpath("state")}/jig/channel.json`.
- Jig does not auto-switch git refs; channel is explicit metadata used by operational workflows.

## Verification
```bash
pattern='(nvim[-_]workbench|nvim(workbench)|nvim[-]2026|nvim(2026)|[N]vimWorkbench|[D]istroHealth|:[D]istro|distro[-]safe|distro[.])'
rg -n "$pattern" . && exit 1 || true
lua -e 'package.path="./lua/?.lua;./lua/?/init.lua;"..package.path; assert(require("jig.spec.requirements").self_check())'
rg -n "MUST|SHOULD|MAY" docs/contract.jig.nvim.md
nvim --headless -u ./init.lua '+lua print("jig-smoke")' '+qa'
nvim --headless -u ./init.lua '+lua assert(vim.g.jig_profile=="default")' '+qa'
NVIM_APPNAME=jig-safe nvim --headless -u ./init.lua '+lua assert(vim.g.jig_profile=="safe")' '+qa'
nvim --headless -u ./init.lua '+checkhealth jig' '+qa'
nvim --headless -u NONE -l tests/run_harness.lua -- --all
tests/check_hidden_unicode.sh
nvim --headless -u NONE -l tests/check_quarantine.lua
nvim --headless -u NONE -l tests/check_pending.lua
tests/perf/run_harness.sh
```

## Documentation
- `SECURITY.md`
- `SUPPORT.md`
- `docs/install.jig.nvim.md`
- `docs/contract.jig.nvim.md`
- `docs/keymaps.jig.nvim.md`
- `doc/jig-keymaps.txt` (`:help jig-keymaps`)
- `docs/architecture.jig.nvim.md`
- `docs/plugin-manager.jig.nvim.md`
- `docs/profiling.jig.nvim.md`
- `docs/navigation.jig.nvim.md`
- `docs/workbench.jig.nvim.md`
- `docs/lsp.jig.nvim.md`
- `docs/tools.jig.nvim.md`
- `docs/agents.jig.nvim.md`
- `docs/security.jig.nvim.md`
- `docs/platform.jig.nvim.md`
- `docs/testing.jig.nvim.md`
- `docs/ui-foundation.jig.nvim.md`
- `docs/ui-testing.jig.nvim.md`
- `docs/maintenance.jig.nvim.md`
- `docs/stability.jig.nvim.md`
- `docs/compatibility.jig.nvim.md`
- `docs/troubleshooting.jig.nvim.md`
- `docs/roadmap/NEOVIM_ROADMAP_ALIGNMENT.md`
- `doc/jig-lsp.txt` (`:help jig-lsp`)
- `doc/jig-workbench.txt` (`:help jig-workbench`)
- `doc/jig-tools.txt` (`:help jig-tools`)
- `doc/jig-agents.txt` (`:help jig-agents`)
- `doc/jig-security.txt` (`:help jig-security`)
- `doc/jig-platform.txt` (`:help jig-platform`)
- `doc/jig-testing.txt` (`:help jig-testing`)

## Support and Security
- Support workflow: `SUPPORT.md`
- Security disclosure policy: `SECURITY.md`
- Security controls and boundaries: `docs/security.jig.nvim.md` and `:help jig-security`

## License
MIT
