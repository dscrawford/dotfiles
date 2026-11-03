#!/usr/bin/env bash
# Drives the pinned agent-shell (shared/emacs/custom-packages.nix) against
# scooter-acp and a fake Scooter. Builds an Emacs with those packages on first run.
set -euo pipefail
cd "$(dirname "$0")/../.."
root=$PWD
tmp=$(mktemp -d)
trap 'kill "${server:-}" 2>/dev/null || true; rm -rf "$tmp"' EXIT

emacs=$(nix build --no-link --print-out-paths --impure --expr "
  let
    flake = builtins.getFlake \"git+file://$root\";
    pkgs = import flake.inputs.nixpkgs { system = builtins.currentSystem; };
  in (pkgs.emacsPackagesFor pkgs.emacs-nox).emacsWithPackages (epkgs:
    let custom = import $root/shared/emacs/custom-packages.nix { inherit pkgs epkgs; };
    in [ custom.acp custom.shell-maker custom.agent-shell ])")

mkdir -p "$tmp/bridge/bin"
printf '#!/bin/sh\nexec node %s/pkgs/scooter-acp/src/main.mjs "$@"\n' "$root" > "$tmp/bridge/bin/scooter-acp"
chmod +x "$tmp/bridge/bin/scooter-acp"
echo "_oauth2_proxy=good" > "$tmp/cookie"
{
  nix eval --raw --impure --expr '(import ./shared/emacs/guard.nix { })'
  echo
  nix eval --raw --impure --expr "(import ./shared/emacs/scooter.nix {
    pkgs.callPackage = _: _: \"$tmp/bridge\";
    config.my.scooter = { url = \"\"; cookieFile = \"$tmp/cookie\"; };
  })"
} > "$tmp/scooter.el"

export TRIGGER_FILE="$tmp/trigger"
node tests/scooter-acp/e2e-server.mjs > "$tmp/url" &
server=$!
for _ in $(seq 50); do [ -s "$tmp/url" ] && break; sleep 0.1; done

SCOOTER_URL=$(cat "$tmp/url") SCOOTER_EL="$tmp/scooter.el" HOME="$tmp" \
  "$emacs/bin/emacs" -Q --batch -l tests/scooter-acp/agent-shell-e2e.el
