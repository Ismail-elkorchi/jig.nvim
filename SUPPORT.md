# Support

Jig support is issue-driven and evidence-first. Use the GitHub issue templates:
- `https://github.com/Ismail-elkorchi/jig.nvim/issues/new/choose`

Canonical docs:
- `docs/troubleshooting.jig.nvim.md` (`:help jig-troubleshooting`)
- `docs/runbooks/INCIDENTS.md`
- `docs/runbooks/ROLLBACK.md`

## Before opening an issue

Run and attach outputs:

```bash
nvim --version
nvim --headless -u ./init.lua '+checkhealth jig' '+qa'
nvim --headless -u ./init.lua '+JigHealth' '+qa'
nvim --headless -u ./init.lua '+JigVersion' '+qa'
NVIM_APPNAME=jig-safe nvim --headless -u ./init.lua '+JigVersion' '+qa'
```

If startup is unstable:

```bash
NVIM_APPNAME=jig-safe nvim -u ./init.lua
nvim --startuptime /tmp/jig.startuptime.log -u ./init.lua '+qa'
```

## Failure-surface triage

Classify the report under one failure surface:
- startup
- cmdline
- completion
- lsp
- ui
- performance
- platform
- integration
- agent
- security

## Boundaries

- Support guidance does not guarantee compatibility with every terminal/font/plugin combination.
- Recovery instructions prioritize deterministic rollback and minimal profile isolation.
