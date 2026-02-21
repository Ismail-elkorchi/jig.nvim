#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
snapshot="${repo_root}/tests/security/snapshots/latest-headless.json"

mkdir -p "$(dirname "$snapshot")"

nvim --headless -u NONE \
  "+lua _G.__jig_repo_root='${repo_root}'" \
  "+lua _G.__jig_security_snapshot='${snapshot}'" \
  "+lua local ok,err=pcall(function() package.path='${repo_root}/lua/?.lua;${repo_root}/lua/?/init.lua;'..package.path; vim.opt.rtp:prepend('${repo_root}'); require('jig'); require('jig.tests.security.harness').run({ snapshot_path = _G.__jig_security_snapshot }) end); if not ok then vim.api.nvim_err_writeln(err); vim.cmd('cquit 1') end" \
  "+qa"

echo "Security harness passed. Snapshot: ${snapshot}"
