#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

pattern='[\x{202A}-\x{202E}\x{2066}-\x{2069}\x{200B}\x{200C}\x{200D}\x{FEFF}]'
if rg -n --pcre2 "$pattern" . ; then
  echo "hidden/bidi unicode characters detected"
  exit 1
fi

echo "hidden/bidi unicode gate passed"
