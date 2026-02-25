#!/usr/bin/env bash
set -euo pipefail

repo="${1:-}"
if [[ -z "$repo" ]]; then
  repo="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
fi

manifest=".github/labels.md"
if [[ ! -f "$manifest" ]]; then
  echo "labels manifest not found: $manifest" >&2
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "gh cli is required" >&2
  exit 1
fi

while IFS='|' read -r _raw name color description _tail; do
  name="$(echo "$name" | xargs)"
  color="$(echo "$color" | xargs)"
  description="$(echo "$description" | xargs)"

  [[ -z "$name" || "$name" == "name" || "$name" == "---" ]] && continue
  [[ -z "$color" || -z "$description" ]] && continue

  gh label create "$name" \
    --repo "$repo" \
    --color "$color" \
    --description "$description" \
    --force
done < <(grep '^|' "$manifest")

echo "label sync complete for $repo"
