#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

nvim --headless -u NONE -l tests/run_harness.lua -- --suite security

echo "Security harness passed. Snapshot: ${repo_root}/tests/security/snapshots/latest-headless.json"
