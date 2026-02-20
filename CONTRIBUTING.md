# contributing.jig.nvim

## Workflow
1. Create a branch from `main`.
2. Open a focused pull request.
3. Run local verification commands (`rg` brand guard + headless smoke + health).
4. Merge only after CI passes.

## Required PR Evidence
- Exact verification commands and outputs.
- At least two plausible failure modes and a discriminating check for each.
- Rollback notes.

## Naming and Branding Rules
- Use `lua/jig/**` for runtime modules.
- User commands must start with `Jig` (for example `:JigChannel`).
- Autocmd groups and highlight groups must use `Jig*`.
- No legacy naming prefixes may remain after rebrand.

## Compatibility Rules
- Do not introduce Neovim APIs deprecated in `0.11+`.
- Prefer native APIs over wrappers unless an adapter is required and documented.
