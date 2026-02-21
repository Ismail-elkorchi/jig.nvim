# contract.jig.nvim.md

Canonical help: `:help jig`

This document is the normative contract for Jig runtime behavior.
`MUST`, `SHOULD`, and `MAY` are interpreted as RFC keywords.

## Section 0: Scope
- `S0-R01` MUST provide a portable, maintainable Neovim configuration system.
- `S0-R02` MUST NOT force a single workflow ideology.

## Section 1: Compatibility and Portability
- `S1-R01` MUST enforce minimum Neovim version with deterministic diagnostics.
- `S1-R02` SHOULD support profile isolation via `NVIM_APPNAME`.

## Section 2: Installation, Updates, Reproducibility
- `S2-R01` MUST keep plugin lifecycle operations explicit.
- `S2-R02` MUST NOT auto-install plugins on startup by default.

## Section 3: Observability and Troubleshooting
- `S3-R01` MUST provide a doctor/health entrypoint with actionable output.
- `S3-R02` SHOULD provide safe-mode startup with optional modules disabled.

## Section 4: External Dependencies and Tooling
- `S4-R01` MUST detect missing providers/binaries and provide remediation guidance.

## Section 5: Performance and Initialization Discipline
- `S5-R01` MUST avoid unnecessary startup side effects and eager heavy work.

## Section 6: UX Defaults and Documentation
- `S6-R01` MUST document default commands and keymaps.

## Section 7: Security Posture
- `S7-R01` MUST NOT execute startup network operations without explicit user action.

## Section 8: Architecture Requirements
- `S8-R01` MUST preserve modular boundaries and user-overridable behavior.

## Section 9: Optional Extensions
- `S9-R01` MAY provide agent integration as an optional removable module.
