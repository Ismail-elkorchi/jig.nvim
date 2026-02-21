# ui-testing.jig.nvim.md

Canonical help: `:help jig-testing`

## Headless Child-UI Harness
Run:
```bash
tests/ui/run_harness.sh
```

This launches a child Neovim process in headless mode and writes screen-state snapshots to:
- `tests/ui/snapshots/latest-headless.json`

The harness verifies:
- semantic highlight API groups
- statusline/winbar active vs inactive policy
- cmdline open/close behavior
- float border/elevation/collision policy
- ASCII fallback legibility

## Timing-Sensitive Tests
Timing-sensitive cases are explicitly labeled `timing-sensitive`.
They include retry policy and bounded retry delay in harness metadata.

## Screenshot/Reference Image Contract
- Reference screenshots are allowed only under deterministic harness contract:
  - pinned terminal emulator version in CI, or
  - local-only capture workflow with recorded terminal version.
- This repo currently uses text snapshots in CI and does not rely on image diffing.
