# Security Policy

Jig uses a **containment-first** security posture:
- deny/ask/allow policy gates for risky operations
- explicit audit logging and attribution
- deterministic security regression tests

Jig does **not** claim perfect prevention. See `docs/security.jig.nvim.md` and `:help jig-security` for boundaries and current threat model coverage.

## Reporting a Vulnerability

Preferred channel (private):
- GitHub Security Advisory draft:  
  `https://github.com/Ismail-elkorchi/jig.nvim/security/advisories/new`

Fallback (if advisory flow is unavailable):
- Open a GitHub issue with `security` failure surface using the incident template:
  `https://github.com/Ismail-elkorchi/jig.nvim/issues/new/choose`

## What to include

- affected Jig version/commit (`:JigVersion`)
- Neovim version and OS (`:JigVersion`)
- exact reproduction steps
- expected vs actual behavior
- minimal proof-of-concept (non-destructive)

## Scope and boundaries

- No guarantee of protection against every prompt-injection or remote-server integrity risk.
- Security controls are only as strong as user policy decisions and local runtime environment.
- `NVIM_APPNAME=jig-safe` is the recommended recovery profile for incident triage.
