#!/usr/bin/env bash
# Protocol tests for pkgs/scooter-acp against an in-process fake Scooter.
set -euo pipefail
cd "$(dirname "$0")/../.."
node --test tests/scooter-acp/*.test.mjs
