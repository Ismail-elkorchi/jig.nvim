#!/usr/bin/env bash
set -euo pipefail

mode="${1:-ok}"
payload="$(cat)"
method="$(printf '%s' "$payload" | sed -n 's/.*"method":"\([^"]*\)".*/\1/p' | head -n1)"
id="$(printf '%s' "$payload" | sed -n 's/.*"id":\([0-9][0-9]*\).*/\1/p' | head -n1)"
if [[ -z "$id" ]]; then
  id=1
fi

if [[ "$mode" == "malformed" ]]; then
  echo '{bad'
  exit 0
fi

if [[ "$method" == "acp/initialize" ]]; then
  printf '{"jsonrpc":"2.0","id":%s,"result":{"protocol":"acp-stdio","version":"0.1","candidate_only":true}}\n' "$id"
  exit 0
fi

if [[ "$method" == "acp/prompt" ]]; then
  printf '{"jsonrpc":"2.0","id":%s,"result":{"content":"candidate-response","metadata":{"mode":"candidate"}}}\n' "$id"
  exit 0
fi

printf '{"jsonrpc":"2.0","id":%s,"error":{"code":-32601,"message":"method_not_found"}}\n' "$id"
