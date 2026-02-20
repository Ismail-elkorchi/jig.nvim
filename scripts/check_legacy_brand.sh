#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

pattern='(nvim[-_]workbench|nvim(workbench)|nvim[-]2026|nvim(2026)|[N]vimWorkbench|[D]istroHealth|:[D]istro|distro[-]safe|distro[.])'

if rg -n --hidden --glob '!.git/*' --glob '!scripts/check_legacy_brand.sh' "$pattern" .; then
  echo "check_legacy_brand: legacy brand strings detected" >&2
  exit 1
fi

echo "check_legacy_brand: passed"
