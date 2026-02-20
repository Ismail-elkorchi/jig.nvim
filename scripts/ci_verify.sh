#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

./scripts/check_legacy_brand.sh

nvim --headless -u ./init.lua '+lua print("jig-smoke")' '+qa'
nvim --headless -u ./init.lua '+checkhealth jig' '+qa'

echo "ci_verify: passed"
