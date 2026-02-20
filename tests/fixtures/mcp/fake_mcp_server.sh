#!/usr/bin/env bash
set -euo pipefail

mode="${1:-ok}"

if [[ "$mode" == "early_exit" ]]; then
  exit 21
fi

if [[ "$mode" == "timeout" ]]; then
  sleep 5
  exit 0
fi

if [[ "$mode" == "malformed" ]]; then
  echo '{not-json'
  exit 0
fi

payload="$(cat)"
id="$(printf '%s' "$payload" | sed -n 's/.*"id":\([0-9][0-9]*\).*/\1/p' | head -n1)"
if [[ -z "$id" ]]; then
  id=1
fi

method="$(printf '%s' "$payload" | sed -n 's/.*"method":"\([^"]*\)".*/\1/p' | head -n1)"

if [[ "$method" == "initialize" ]]; then
  printf '{"jsonrpc":"2.0","id":%s,"result":{"server":"fake-mcp","capabilities":{"tools":true}}}\n' "$id"
  exit 0
fi

if [[ "$method" == "tools/list" ]]; then
  echo '{"jsonrpc":"2.0","id":1,"result":{"tools":[{"name":"echo"},{"name":"danger"}]}}'
  exit 0
fi

if [[ "$method" == "tools/call" ]]; then
  tool_name="$(printf '%s' "$payload" | sed -n 's/.*"name":"\([^"]*\)".*/\1/p' | head -n1)"
  if [[ "$mode" == "tool_not_found" || "$tool_name" != "echo" ]]; then
    printf '{"jsonrpc":"2.0","id":%s,"result":{"error":"tool_not_found"}}\n' "$id"
    exit 0
  fi

  message="$(printf '%s' "$payload" | sed -n 's/.*"message":"\([^"]*\)".*/\1/p' | head -n1)"
  if [[ -z "$message" ]]; then
    message="ok"
  fi
  printf '{"jsonrpc":"2.0","id":%s,"result":{"content":"%s"}}\n' "$id" "$message"
  exit 0
fi

printf '{"jsonrpc":"2.0","id":%s,"error":{"code":-32601,"message":"method_not_found"}}\n' "$id"
