#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

# Coverage:
# - Bidi controls (U+202A..U+202E, U+2066..U+2069)
# - Zero-width and BOM markers (U+200B/U+200C/U+200D/U+FEFF)
# - Directionality marks and related invisible controls
#   (U+200E LRM, U+200F RLM, U+061C ALM, U+2060 WORD JOINER, U+00AD SOFT HYPHEN)
pattern='[\x{202A}-\x{202E}\x{2066}-\x{2069}\x{200B}\x{200C}\x{200D}\x{FEFF}\x{200E}\x{200F}\x{061C}\x{2060}\x{00AD}]'

fixture_path='tests/fixtures/security/hidden_unicode_fixture.txt'

declare -a scan_files=()
while IFS= read -r -d '' file; do
  if [[ "$file" == "$fixture_path" ]]; then
    continue
  fi
  scan_files+=("$file")
done < <(git ls-files -z)

if ((${#scan_files[@]} > 0)); then
  if rg -n --pcre2 "$pattern" "${scan_files[@]}"; then
    echo "hidden/bidi unicode characters detected in tracked files"
    exit 1
  fi
fi

if [[ ! -f "$fixture_path" ]]; then
  echo "hidden unicode fixture is missing: $fixture_path"
  exit 1
fi

if ! rg -n --pcre2 "$pattern" "$fixture_path" >/dev/null; then
  echo "hidden unicode fixture did not trigger detection pattern"
  exit 1
fi

echo "hidden/bidi unicode gate passed"
