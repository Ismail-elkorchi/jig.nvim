#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

nvim --headless -u NONE -l tests/run_harness.lua -- --suite agent_ui

echo "Agent UI harness passed. Snapshot: ${repo_root}/tests/agent_ui/snapshots/latest-headless.json"
