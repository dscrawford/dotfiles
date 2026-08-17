#!/usr/bin/env bash
# Unit and stdio-protocol tests for pkgs/local-llm-mcp. Ollama is mocked
# with a local HTTP server; no models or GPU needed.
set -euo pipefail
cd "$(dirname "$0")/../.."
node --test tests/local-llm-mcp/*.test.mjs
