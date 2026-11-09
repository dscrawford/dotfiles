#!/usr/bin/env bash
# Drives the pinned agent-shell and scooter-mode (shared/emacs/custom-packages.nix,
# shared/emacs/scooter-mode.nix) through the dotfiles' Scooter config against
# `scooter acp` and a fake Scooter. Builds Emacs and the bridge on first run.
set -euo pipefail
cd "$(dirname "$0")/../.."
root=$PWD
tmp=$(mktemp -d)
trap 'kill "${server:-}" 2>/dev/null || true; rm -rf "$tmp"' EXIT

pkgs="(import (builtins.getFlake \"git+file://$root\").inputs.nixpkgs { system = builtins.currentSystem; })"
build() { nix build --no-link --print-out-paths --impure --expr "let pkgs = $pkgs; in $1"; }

emacs=$(build "(pkgs.emacsPackagesFor pkgs.emacs-nox).emacsWithPackages (epkgs:
    let custom = import $root/shared/emacs/custom-packages.nix { inherit pkgs epkgs; };
    in [ custom.acp custom.shell-maker custom.agent-shell custom.scooter ])")
build "(import $root/shared/emacs/scooter-mode.nix { inherit pkgs; }).bridge" > /dev/null
node=$(build "pkgs.nodejs")

{
  echo ";; -*- lexical-binding: t -*-"
  nix eval --raw --impure --expr '(import ./shared/emacs/guard.nix { })'
  echo
  nix eval --raw --impure --expr "(import ./shared/emacs/scooter.nix {
    pkgs = $pkgs;
    config.my.scooter.url = \"\";
  })"
} > "$tmp/scooter.el"

export TRIGGER_FILE="$tmp/trigger"
"$node/bin/node" tests/scooter/e2e-server.mjs > "$tmp/url" &
server=$!
for _ in $(seq 50); do [ -s "$tmp/url" ] && break; sleep 0.1; done

# auth-source writes the test cookie to this HOME's ~/.authinfo.
SCOOTER_URL=$(cat "$tmp/url") SCOOTER_EL="$tmp/scooter.el" HOME="$tmp" \
  "$emacs/bin/emacs" -Q --batch \
  --eval '(setq auth-sources (list (expand-file-name "authinfo" (getenv "HOME"))) auth-source-save-behavior t)' \
  -l tests/scooter/agent-shell-e2e.el
