# navigation.jig.nvim.md

## Root Resolution Policy
Jig resolves navigation root in deterministic order:
1. `JIG_ROOT` environment variable (if set)
2. `:JigRootSet` command override
3. marker search using `vim.fs.root` with ordered markers
4. current working directory fallback

Default marker priority:
- `jig.root`
- `.git`
- `package.json`
- `pyproject.toml`
- `go.mod`
- `Cargo.toml`
- `Makefile`

Override commands:
```vim
:JigRootSet /absolute/or/relative/path
:JigRootReset
```

## Navigation Commands
All commands are root-policy aware and degrade gracefully when plugin backends are unavailable:
- `:JigFiles`
- `:JigBuffers`
- `:JigRecent`
- `:JigSymbols`
- `:JigDiagnostics`
- `:JigHistory`
- `:JigGitChanges`

## Backend Strategy
Default backend:
- Snacks picker when available and healthy

Fallback backend:
- file lists: `git ls-files` or `rg --files`, then `vim.ui.select` (or non-interactive first-item behavior in headless)
- buffers/recent/diagnostics/history/git changes: built from Neovim state and shell output

Fallback is automatic on backend error or missing picker source.

## Large-Repo Guardrails
Jig enforces bounded candidate sets:
- candidate caps are always applied
- git repositories are detected with `git rev-parse`
- large-repo detection uses `git ls-files -z` count
- when repo file count exceeds threshold, a lower cap is applied

Configurable defaults (`vim.g.jig_nav`):
```lua
vim.g.jig_nav = {
  candidate_cap = 500,
  large_repo_threshold = 15000,
  large_repo_cap = 200,
  ignore_globs = {
    "!.git/*",
    "!node_modules/*",
    "!dist/*",
    "!build/*",
    "!target/*",
    "!coverage/*",
    "!.cache/*",
  },
  enable_miller = false,
}
```

## Optional Miller Mode
Miller columns are optional and disabled by default.

Enable:
```lua
vim.g.jig_nav = vim.tbl_deep_extend("force", vim.g.jig_nav or {}, {
  enable_miller = true,
})
```

Command:
```vim
:JigMiller
```

When disabled, `:JigMiller` returns a non-fatal informational message.
