# platform.jig.nvim.md

## Purpose
WP-11 turns cross-platform behavior into a verified property using:
- a dedicated platform abstraction layer (`lua/jig/platform/*`)
- a cross-platform Lua harness runner (`tests/run_harness.lua`)
- CI matrix lanes per OS/arch target

## Platform Layer
Modules:
- `lua/jig/platform/os.lua`
- `lua/jig/platform/path.lua`
- `lua/jig/platform/fs.lua`
- `lua/jig/platform/clipboard.lua`
- `lua/jig/platform/shell.lua`
- `lua/jig/platform/init.lua`

Policy:
- OS/shell detection is centralized in `jig.platform.*`.
- Existing tool-facing compatibility adapter remains at `lua/jig/tools/platform.lua` and delegates to `jig.platform`.

## Verified Workflows
Cross-platform harness runner:
```bash
nvim --headless -u NONE -l tests/run_harness.lua -- --all
```

Default suite set:
- startup smoke
- cmdline open/close
- ui harness
- keymap harness
- navigation harness
- tools harness
- security harness
- platform harness

Platform harness invariants:
- path join/normalize idempotence
- stdpath availability (`config`, `data`, `state`, `cache`)
- shell detection + argv-first one-liner strategy
- clipboard detection remains non-fatal with actionable hint
- root detection stable for normalized path inputs

## CI Matrix Scope
Target lanes:
- Linux x86_64
- Linux arm64
- macOS arm64
- macOS intel
- Windows native

WSL lane:
- best-effort and non-blocking on hosted runners
- if hosted limitations block reproducibility, self-hosted WSL runner is required for gating

## WSL Self-Hosted Plan
1. Provision Windows host with WSL2 and Ubuntu.
2. Install Git, Neovim, ripgrep, and runner dependencies inside the WSL environment.
3. Register a self-hosted GitHub Actions runner from inside WSL with labels:
   - `self-hosted`
   - `linux`
   - `x64`
   - `wsl`
   - `jig-wsl`
4. Add CI lane targeting `runs-on: [self-hosted, linux, x64, wsl, jig-wsl]`.
5. Run:
   ```bash
   nvim --headless -u NONE -l tests/run_harness.lua -- --all
   ```

## Scope of Guarantees
Verified by CI:
- startup + command-surface stability
- key navigation/tool/security workflows across matrix lanes
- path and shell invariants from platform harness

User-verified (outside hosted CI):
- WSL lane if hosted runner cannot provide deterministic WSL semantics
- workstation-specific shell/plugin edge-cases not covered by fixture suite

## Non-Guarantees
- No claim of perfect semantic parity for every shell plugin on every OS.
- Security controls are scoped guardrails, not full sandboxing.
