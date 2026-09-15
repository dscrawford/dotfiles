#!/usr/bin/env bash
# Tests for the scrolling and defun-navigation modules. Extracts their elisp
# from the nix modules (no build) and runs the ERT suite in batch Emacs.
set -euo pipefail
cd "$(dirname "$0")/../.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
for module in scrolling navigation guard; do
  nix eval --raw --impure --expr "(import ./shared/emacs/$module.nix { })" \
    > "$tmp/$module.el"
done

# Only gates the upstream contract test, so a failure here just skips it.
sj=$(nix build --no-link --print-out-paths nixpkgs#emacsPackages.scroll-on-jump 2>/dev/null || true)
sj_el=$([ -n "$sj" ] && find "$sj" -name scroll-on-jump.el -print -quit || true)

SCROLLING_EL="$tmp/scrolling.el" NAVIGATION_EL="$tmp/navigation.el" \
  GUARD_EL="$tmp/guard.el" SCROLL_ON_JUMP_DIR="$(dirname "${sj_el:-.}")" \
  emacs -Q --batch -l ert -l tests/emacs/scroll-nav-test.el \
  -f ert-run-tests-batch-and-exit
