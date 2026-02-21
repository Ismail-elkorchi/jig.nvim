# safety-model.jig.nvim.md

Canonical help: `:help jig-safety`

## Model
- Explicit operations over hidden automation.
- Startup non-essential network denied by default guardrails.
- Policy-routed risky actions where implemented.
- Safe profile isolation for recovery and triage.

## Recovery First
```bash
NVIM_APPNAME=jig-safe nvim
```

Use:
```vim
:JigDocs
:JigRepro
:JigHealth
```

## Boundaries
- Guardrails reduce risk classes; they do not guarantee total protection.
- User overrides can intentionally expand risk surface.
- External tools and MCP servers remain separate failure domains.
