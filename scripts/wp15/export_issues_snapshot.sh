#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

if ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI is required to export issues snapshot" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required to shape issues snapshot JSON" >&2
  exit 1
fi

tmp_raw="$(mktemp)"
trap 'rm -f "$tmp_raw"' EXIT

gh api --method GET --paginate repos/Ismail-elkorchi/jig.nvim/issues -f state=all -f per_page=100 >"$tmp_raw"

jq '
  map(select(.pull_request | not))
  | {
      retrieved_at: (now | strftime("%Y-%m-%dT%H:%M:%SZ")),
      repo: "Ismail-elkorchi/jig.nvim",
      issue_count: length,
      issues: map({
        number,
        title,
        state,
        created_at,
        updated_at,
        closed_at,
        labels: [.labels[].name],
        html_url
      })
    }
' "$tmp_raw" >data/wp15/issues_snapshot.json

echo "Updated data/wp15/issues_snapshot.json"
