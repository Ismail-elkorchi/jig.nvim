#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
scan_root="${repo_root}/lua/jig"

find_runtime() {
  local runtime
  runtime="$(nvim --headless -u NONE '+lua io.write(vim.env.VIMRUNTIME or "")' '+qa' 2>/dev/null || true)"
  if [[ -n "$runtime" && -f "$runtime/doc/deprecated.txt" ]]; then
    printf '%s\n' "$runtime"
    return 0
  fi

  runtime="$(nvim --headless -u NONE '+lua local paths=vim.api.nvim_get_runtime_file("doc/deprecated.txt", false); if paths[1] then io.write(vim.fn.fnamemodify(paths[1], ":h:h")) end' '+qa' 2>/dev/null || true)"
  if [[ -n "$runtime" && -f "$runtime/doc/deprecated.txt" ]]; then
    printf '%s\n' "$runtime"
    return 0
  fi

  for candidate in \
    "${VIMRUNTIME:-}" \
    "/usr/share/nvim/runtime" \
    "/usr/local/share/nvim/runtime"
  do
    if [[ -n "$candidate" && -f "$candidate/doc/deprecated.txt" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

runtime="$(find_runtime || true)"
if [[ -z "$runtime" ]]; then
  echo "could not locate Neovim runtime/deprecated.txt"
  exit 1
fi

deprecated_file="${runtime}/doc/deprecated.txt"
if [[ ! -f "$deprecated_file" ]]; then
  echo "missing deprecated doc: ${deprecated_file}"
  exit 1
fi

symbols_file="$(mktemp)"
hits_file="$(mktemp)"
trap 'rm -f "$symbols_file" "$hits_file"' EXIT

{
  perl -ne 'while(/\*([^*]+)\*/g){ print "$1\n" }' "$deprecated_file"
  perl -ne 'if(/^\s*•\s*([A-Za-z0-9_.:]+)\(\)/){ print "$1\n" }' "$deprecated_file"
} \
  | sed -E 's/[`|]//g; s/\(\)$//; s/[[:space:]].*$//; s/^[*]+//; s/[*]+$//' \
  | rg -N '^(vim\.|nvim_|client\.)' \
  | sort -u > "$symbols_file"

if [[ ! -s "$symbols_file" ]]; then
  echo "deprecated symbol extraction returned empty set"
  exit 1
fi

while IFS= read -r symbol; do
  [[ -z "$symbol" ]] && continue

  patterns=()
  if [[ "$symbol" == nvim_* ]]; then
    patterns+=("${symbol}(")
  elif [[ "$symbol" == client.* ]]; then
    method="${symbol#client.}"
    patterns+=("${symbol}(" "client:${method}(")
  else
    patterns+=("$symbol")
  fi

  for pattern in "${patterns[@]}"; do
    if rg -n --fixed-strings --glob '!lua/jig/tests/**' "$pattern" "$scan_root" >> "$hits_file"; then
      printf 'deprecated symbol matched: %s\n' "$pattern" >> "$hits_file"
    fi
  done
done < "$symbols_file"

if [[ -s "$hits_file" ]]; then
  echo "deprecated API usage detected in maintained modules"
  cat "$hits_file"
  exit 1
fi

echo "deprecated API gate passed (${deprecated_file})"
