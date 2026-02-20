# architecture.jig.nvim.md

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
- `core/plugin_state.lua`: install/update/restore/rollback lifecycle commands.
- `core/health.lua`: health provider used by `:checkhealth jig`.
- `nav/root.lua`: deterministic root resolution policy.
- `nav/guardrails.lua`: large-repo caps and ignore policies.
- `nav/backend.lua`: picker backend bridge with fallback routing.
- `nav/fallback.lua`: builtin command-safe fallback navigation paths.
- `nav/miller.lua`: optional Miller-column mode module.
- `ui/init.lua`: UI policy wiring (tokens, profiles, chrome, cmdline checks).
- `ui/tokens.lua`: semantic highlight token system.
- `ui/chrome.lua`: active/inactive statusline + winbar policy.
- `ui/float.lua`: border hierarchy, elevation model, collision policy.
- `ui/icons.lua`: Nerd Font/ASCII icon mode adapter.

## Plugin Layers
- `plugins/ui.lua`: colorscheme, icons, keymap discovery UI.
- `plugins/find.lua`: picker/navigation.
- `plugins/lsp.lua`: native LSP + Mason.
- `plugins/completion.lua`: completion stack with stable fallback.
- `plugins/git.lua`: git signs and hunk state.
- `plugins/syntax.lua`: treesitter highlighting/indent.

## Policy
- Stability-first defaults.
- Native API alignment with Neovim 0.11+.
- ASCII fallback for iconography.
- PR-only + linear-history governance on `main`.
- Optional extensions (including agent modules) must be removable without breaking core startup.
