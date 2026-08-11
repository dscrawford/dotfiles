#!/usr/bin/env bash
# Regression tests for the agent-shell process-leak fixes (RUFLO_BUG.md).
# Extracts the elisp from shared/emacs/agent-shell.nix (pkgs faked, no build)
# and runs the ERT suite in batch Emacs. Set ACP_DIR to a directory
# containing acp.el to enable the contract test; it skips otherwise.
set -euo pipefail
cd "$(dirname "$0")/../.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
nix eval --raw --impure --expr \
  '(import ./shared/emacs/agent-shell.nix { pkgs = { callPackage = _: _: "/test-claude-agent-acp"; }; }).agentShell' \
  > "$tmp/agent-shell.el"
AGENT_SHELL_EL="$tmp/agent-shell.el" \
  emacs -Q --batch -l ert -l tests/emacs/agent-shell-leak-test.el \
  -f ert-run-tests-batch-and-exit
