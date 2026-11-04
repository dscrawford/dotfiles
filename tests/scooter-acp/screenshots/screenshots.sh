#!/usr/bin/env bash
# Regenerates docs/images/scooter-acp/*.png: a GUI Emacs with the pinned
# agent-shell, under Xvfb, driven against scooter-acp and a demo fake Scooter.
set -euo pipefail
cd "$(dirname "$0")/../../.."
root=$PWD
out=${1:-$root/docs/images/scooter-acp}
tmp=$(mktemp -d)
trap 'kill "${server:-}" 2>/dev/null || true; rm -rf "$tmp"' EXIT
mkdir -p "$out"

build() { nix build --no-link --print-out-paths --impure --expr "
  let
    flake = builtins.getFlake \"git+file://$root\";
    pkgs = import flake.inputs.nixpkgs { system = builtins.currentSystem; };
  in $1"; }

emacs=$(build "(pkgs.emacsPackagesFor pkgs.emacs).emacsWithPackages (epkgs:
    let custom = import $root/shared/emacs/custom-packages.nix { inherit pkgs epkgs; };
    in [ custom.acp custom.shell-maker custom.agent-shell epkgs.markdown-mode ])")
fonts=$(build "pkgs.makeFontsConf { fontDirectories = [ pkgs.dejavu_fonts pkgs.noto-fonts ]; }")
xvfb=$(build "pkgs.xvfb-run")
node=$(build "pkgs.nodejs")

mkdir -p "$tmp/bridge/bin"
printf '#!/bin/sh\nexec %s/bin/node %s/pkgs/scooter-acp/src/main.mjs "$@"\n' "$node" "$root" > "$tmp/bridge/bin/scooter-acp"
chmod +x "$tmp/bridge/bin/scooter-acp"
echo "_oauth2_proxy=good" > "$tmp/cookie"
{
  echo ";; -*- lexical-binding: t -*-"
  nix eval --raw --impure --expr '(import ./shared/emacs/guard.nix { })'
  echo
  nix eval --raw --impure --expr "(import ./shared/emacs/scooter.nix {
    pkgs.callPackage = _: _: \"$tmp/bridge\";
    config.my.scooter = { url = \"\"; cookieFile = \"$tmp/cookie\"; };
  })"
} > "$tmp/scooter.el"

export TRIGGER_FILE="$tmp/trigger"
"$node/bin/node" tests/scooter-acp/screenshots/demo-server.mjs > "$tmp/url" &
server=$!
for _ in $(seq 50); do [ -s "$tmp/url" ] && break; sleep 0.1; done

mkdir -p "$tmp/home/project"
cd "$tmp/home/project"
SCOOTER_URL=$(cat "$tmp/url") SCOOTER_EL="$tmp/scooter.el" SHOTS_DIR="$out" HOME="$tmp/home" \
  FONTCONFIG_FILE="$fonts" PATH="$node/bin:$PATH" \
  timeout 180 "$xvfb/bin/xvfb-run" -a -s "-screen 0 1920x1080x24" \
  "$emacs/bin/emacs" -Q -l "$root/tests/scooter-acp/screenshots/drive.el"
