#!/usr/bin/env bash
# Regenerates docs/images/scooter-acp/*.png: a GUI Emacs with the pinned
# agent-shell and scooter-mode, under Xvfb, driven through the dotfiles'
# Scooter config against `scooter acp` and a demo fake Scooter.
set -euo pipefail
cd "$(dirname "$0")/../../.."
root=$PWD
out=${1:-$root/docs/images/scooter-acp}
tmp=$(mktemp -d)
trap 'kill "${server:-}" 2>/dev/null || true; rm -rf "$tmp"' EXIT
mkdir -p "$out"

pkgs="(import (builtins.getFlake \"git+file://$root\").inputs.nixpkgs { system = builtins.currentSystem; })"
build() { nix build --no-link --print-out-paths --impure --expr "let pkgs = $pkgs; in $1"; }

emacs=$(build "(pkgs.emacsPackagesFor pkgs.emacs).emacsWithPackages (epkgs:
    let custom = import $root/shared/emacs/custom-packages.nix { inherit pkgs epkgs; };
    in [ custom.acp custom.shell-maker custom.agent-shell custom.scooter epkgs.markdown-mode ])")
build "(import $root/shared/emacs/scooter-mode.nix { inherit pkgs; }).bridge" > /dev/null
fonts=$(build "pkgs.makeFontsConf { fontDirectories = [ pkgs.dejavu_fonts pkgs.noto-fonts ]; }")
xvfb=$(build "pkgs.xvfb-run")
node=$(build "pkgs.nodejs")

{
  echo ";; -*- lexical-binding: t -*-"
  nix eval --raw --impure --expr '(import ./shared/emacs/guard.nix { })'
  echo
  nix eval --raw --impure --expr "let pkgs = $pkgs; in (import ./shared/emacs/scooter.nix {
    inherit pkgs;
    config = (pkgs.lib.evalModules {
      modules = [ ./shared/home/scooter.nix { my.scooter.url = \"\"; } ];
    }).config;
  })"
} > "$tmp/scooter.el"

export TRIGGER_FILE="$tmp/trigger"
"$node/bin/node" tests/scooter/screenshots/demo-server.mjs > "$tmp/url" &
server=$!
for _ in $(seq 50); do [ -s "$tmp/url" ] && break; sleep 0.1; done

mkdir -p "$tmp/home/project"
cd "$tmp/home/project"
SCOOTER_URL=$(cat "$tmp/url") SCOOTER_EL="$tmp/scooter.el" SHOTS_DIR="$out" HOME="$tmp/home" \
  FONTCONFIG_FILE="$fonts" PATH="$node/bin:$PATH" \
  timeout 180 "$xvfb/bin/xvfb-run" -a -s "-screen 0 1920x1080x24" \
  "$emacs/bin/emacs" -Q -l "$root/tests/scooter/screenshots/drive.el"
