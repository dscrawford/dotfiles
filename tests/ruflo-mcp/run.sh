#!/usr/bin/env bash
# Supervisor tests for pkgs/ruflo-mcp. ruflo itself is replaced by a fake
# stdio MCP server that crashes and hangs on command; nothing real is spawned.
set -euo pipefail
cd "$(dirname "$0")/../.."
node --test tests/ruflo-mcp/*.test.mjs
