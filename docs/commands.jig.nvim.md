# commands.jig.nvim.md

Generated from the default runtime command surface. Do not edit manually.

| Command | Args | Bang | Description |
|---|---|---|---|
| `:JigBisectGuide` | `none` | `no` | Show deterministic bisect guidance |
| `:JigBuffers` | `optional-one` | `no` | Find buffers filtered by deterministic root |
| `:JigChannel` | `one` | `no` | Set update channel metadata (stable|edge) |
| `:JigCmdlineCheck` | `none` | `no` | Verify native ':' cmdline opens and closes cleanly |
| `:JigDiagnostics` | `optional-one` | `no` | Find diagnostics with fallback behavior |
| `:JigDocs` | `none` | `no` | Open Jig documentation index |
| `:JigExec` | `one-or-more` | `yes` | Run command via Jig system wrapper and show deterministic result |
| `:JigFiles` | `optional-one` | `no` | Find files using deterministic root policy |
| `:JigFloatDemo` | `none` | `no` | Open demo floats using Jig float design policy |
| `:JigGitChanges` | `optional-one` | `no` | Find git changes with fallback behavior |
| `:JigHealth` | `none` | `no` | Run Jig and provider health checks |
| `:JigHistory` | `optional-one` | `no` | Find command history entries |
| `:JigIconMode` | `optional-one` | `no` | Set icon mode (auto|nerd|ascii) |
| `:JigKeys` | `none` | `no` | Show keymap registry index |
| `:JigLspHealth` | `none` | `no` | Show Jig LSP health with remediation |
| `:JigLspInfo` | `none` | `no` | Show enabled LSP servers and current buffer attach state |
| `:JigLspSnapshot` | `optional-one` | `no` | Print JSON snapshot or write LSP state to file |
| `:JigMiller` | `optional-one` | `no` | Open optional Miller-column navigation mode |
| `:JigPluginBootstrap` | `none` | `no` | Install lazy.nvim explicitly (no startup auto-install) |
| `:JigPluginInstall` | `none` | `no` | Install/sync plugins from lock state |
| `:JigPluginRestore` | `none` | `no` | Restore plugins from lazy-lock.json |
| `:JigPluginRollback` | `none` | `no` | Restore previous lockfile backup and run Lazy restore |
| `:JigPluginUpdate` | `none` | `no` | Preview then apply plugin updates (explicit confirm) |
| `:JigRecent` | `optional-one` | `no` | Find recent files filtered by deterministic root |
| `:JigRepro` | `none` | `no` | Print deterministic minimal repro steps |
| `:JigRootReset` | `none` | `no` | Clear deterministic root override |
| `:JigRootSet` | `optional-one` | `no` | Set deterministic root override |
| `:JigSymbols` | `optional-one` | `no` | Find symbols with fallback behavior |
| `:JigTerm` | `optional-one` | `no` | Open integrated terminal (default root or buffer directory) |
| `:JigToolHealth` | `none` | `no` | Show shell, provider, and external tool integration summary |
| `:JigUiProfile` | `optional-one` | `no` | Set accessibility profile (default|high-contrast|reduced-decoration|reduced-motion) |
| `:JigVerboseMap` | `one` | `no` | Show keymap provenance via :verbose map <lhs> |
| `:JigVerboseSet` | `one` | `no` | Show option provenance via :verbose set <option>? |

Canonical help: `:help jig-commands`

