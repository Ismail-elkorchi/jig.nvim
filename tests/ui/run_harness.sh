#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
snapshot="${repo_root}/tests/ui/snapshots/latest-headless.json"

mkdir -p "$(dirname "$snapshot")"

nvim --headless -u "${repo_root}/init.lua" \
  "+lua _G.__jig_snapshot='${snapshot}'" \
  "+lua local ok,err=pcall(function() package.path='${repo_root}/lua/?.lua;${repo_root}/lua/?/init.lua;'..package.path; vim.opt.rtp:prepend('${repo_root}'); require('jig.tests.ui.harness').run({ snapshot_path = _G.__jig_snapshot }) end); if not ok then vim.api.nvim_err_writeln(err); vim.cmd('cquit 1') end" \
  "+qa"

echo "UI harness passed. Snapshot: ${snapshot}"
