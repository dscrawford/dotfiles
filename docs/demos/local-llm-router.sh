#!/usr/bin/env bash
# Demo driver for local-llm-router.tape: asks the local model to draft a
# commit message for a sample diff, via the MCP server over stdio.
set -euo pipefail
cd "$(dirname "$0")/../.."

diff_summary="src/greet.py: greet() gains a name parameter and returns an f-string instead of printing"
call=$(jq -cn --arg d "$diff_summary" \
  '{jsonrpc:"2.0",id:2,method:"tools/call",params:{name:"local_model_run",arguments:{task:$d,profile:"commit-message",maxTokens:2048}}}')

printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"demo","version":"0"}}}' \
  "$call" \
  | node pkgs/local-llm-mcp/server.mjs \
  | jq -r 'select(.id==2) | .result.content[0].text' | head -4
