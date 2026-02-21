#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <base-sha> <head-sha>"
  exit 1
fi

base_sha="$1"
head_sha="$2"

if ! git diff --quiet "$base_sha..$head_sha" -- tests/quarantine.json; then
  added_entries="$(git diff --unified=0 "$base_sha..$head_sha" -- tests/quarantine.json | rg '^\+\s*"[^"]+":' || true)"
  if [[ -n "$added_entries" ]]; then
    if [[ "${PR_BODY:-}" != *"[quarantine-justification]"* ]]; then
      echo "quarantine allowlist grew; add [quarantine-justification] note in PR body"
      echo "$added_entries"
      exit 1
    fi
  fi
fi

echo "quarantine growth check passed"
