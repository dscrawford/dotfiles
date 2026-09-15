#!/usr/bin/env bash
# Window-reuse tests for shared/emacs/kubernetes.nix. Extracts its elisp with
# pkgs faked (no build) and runs the ERT suite in batch Emacs.
set -euo pipefail
cd "$(dirname "$0")/../.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
nix eval --raw --impure --expr \
  '(import ./shared/emacs/kubernetes.nix { pkgs = { kubectl = "/test-kubectl"; }; })' \
  > "$tmp/kubernetes.el"
KUBERNETES_EL="$tmp/kubernetes.el" \
  emacs -Q --batch -l ert -l tests/emacs/kubed-window-test.el \
  -f ert-run-tests-batch-and-exit
