# Jig Engineering Architecture

## Layering
- `lua/jig/core/*`: core runtime and policy defaults.
- `lua/jig/plugins/*`: integration declarations and feature adapters.
- `lua/jig/health.lua`: observability and diagnostics surface.

## Dependency Direction
- Core must not depend on UI/agent implementation details directly.
- External integrations are isolated in plugin modules.
- `vim.api` usage in core requires explicit whitelist marker:
  - `boundary: allow-vim-api`

## Naming Contracts
- Lua namespace: `jig.*`
- User commands: `:Jig*`
- Autocmd groups: `Jig*`
- Health target: `:checkhealth jig`

## Verification Hooks
- CI workflow (`.github/workflows/ci.yml`)
- Legacy brand guard regex in CI
- Roadmap execution board (`docs/roadmap/EXECUTION_BOARD.md`)
