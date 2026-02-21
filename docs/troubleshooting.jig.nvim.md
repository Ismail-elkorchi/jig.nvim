# troubleshooting.jig.nvim.md

Canonical help: `:help jig-troubleshooting`

## Failure-Class Workflow
Use this sequence under failure:
1. capture what failed
2. identify failure surface
3. run the next command

## Failure Surfaces
### startup
- what failed: crash/error before editing.
- why: profile/config/plugin state drift.
- next command:
```bash
NVIM_APPNAME=jig-safe nvim
nvim --startuptime /tmp/jig.startuptime.log -u ./init.lua '+qa'
```

### cmdline
- what failed: `:` opens with errors.
- why: cmdline integration drift.
- next command:
```vim
:JigCmdlineCheck
```

### completion
- what failed: completion unavailable or unstable.
- why: backend/provider mismatch.
- next command:
```bash
nvim --headless -u NONE -l tests/run_harness.lua -- --suite completion
```

### lsp
- what failed: servers fail to attach, diagnostics missing.
- why: server binary/config/runtime mismatch.
- next command:
```vim
:JigLspHealth
:JigLspInfo
```

### ui
- what failed: icons/highlights/chrome unreadable.
- why: terminal/font/profile mismatch.
- next command:
```vim
:JigUiProfile high-contrast
:JigIconMode ascii
```

### performance
- what failed: startup/first-action latency spikes.
- why: regression in startup or first-response path.
- next command:
```bash
nvim --headless -u NONE -l tests/run_harness.lua -- --suite perf
```

### platform
- what failed: OS/shell/path behavior mismatch.
- why: platform abstraction or shell differences.
- next command:
```bash
nvim --headless -u NONE -l tests/run_harness.lua -- --suite platform
```

### integration
- what failed: tools/providers don’t execute as expected.
- why: missing binary/provider/shell mismatch.
- next command:
```vim
:JigToolHealth
:checkhealth jig
```

### agent / security
- what failed: trust/policy/MCP/exec-safety path denied or misbehaving.
- why: policy or trust state.
- next command:
```vim
:JigMcpTrust
:JigAgentPolicyList
```
```bash
nvim --headless -u NONE -l tests/run_harness.lua -- --suite security
```

## Provenance Helpers
```vim
:JigVerboseMap <leader>qq
:JigVerboseSet number
```

## Deterministic Bisect
1. `NVIM_APPNAME=jig-safe nvim`
2. Re-enable optional layers in halves.
3. Keep failing half, repeat.
4. Capture evidence with `:JigHealth` and `:JigRepro`.

## Not Guaranteed / Boundaries
- Some failures require project-specific reproductions.
- Hosted WSL CI lane is best-effort; local verification can still be required.
- Optional agent workflows can be unavailable by policy.
