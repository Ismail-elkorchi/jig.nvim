# CONTRIBUTORS.md

## Local Setup
```bash
git clone https://github.com/Ismail-elkorchi/jig.nvim
cd jig.nvim
```

## Core Local Verification
```bash
stylua --check --config-path .stylua.toml $(rg --files lua tests -g '*.lua')
nvim --headless -u ./init.lua '+checkhealth jig' '+qa'
nvim --headless -u NONE -l tests/run_harness.lua -- --all
```

## Adding a New `:Jig*` Command
1. Add command implementation.
2. Add/update docs entry via command docs generation/check.
3. Add tests in relevant suite.
4. Run docs harness and CI-equivalent commands.

## Adding/Changing Keymaps
1. Change keymap registry (`lua/jig/core/keymap_registry.lua`).
2. Regenerate/check keymap docs.
3. Verify keymap harness passes.

## Required Discipline
- no startup auto-install side effects
- no startup implicit network side effects
- keep `jig-safe` isolated
- do not bypass quarantine/pending CI gates
