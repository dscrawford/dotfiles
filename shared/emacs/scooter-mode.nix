# shared/emacs/scooter-mode.nix
# scooter-mode (github.com/chadac-me/scooter-mode): the `scooter` bridge
# (`scooter acp`, an ACP agent for agent-shell) and its Emacs package, built
# from one pinned source so the two always match.
#
# Pinned to feat/kanban on the dscrawford fork: combined/dcraw (chadac-me#19
# plus the open PRs #20-#24: mid-session sign-in, Firefox login, answer
# delivery, sandbox path links, push race), dscrawford#1 (kanban boards),
# dscrawford#4 (Firefox cookie without the paste prompt) and dscrawford#5
# (oauth2-proxy --cookie-name, which scooter.dcraw.net uses; any browser's
# cookie jar; one sign-in wait per command).
# Move back to chadac-me once those merge.
{ pkgs }:

let
  version = "0.1.0-unstable-2026-11-11";
  src = pkgs.fetchFromGitHub {
    owner = "dscrawford";
    repo = "scooter-mode";
    rev = "9ce25c29441c87f9de7bb59ef19c019ead2fa247";
    hash = "sha256-7dYIu/G1a3loiBIugUVFWFpKArVBeulhoZyVbRFADog=";
  };
in
{
  inherit src version;

  bridge = pkgs.buildGoModule {
    pname = "scooter";
    inherit version src;
    subPackages = [ "cmd/scooter" ];
    vendorHash = null;
    ldflags = [ "-s" "-w" "-X main.version=${version}" ];
    meta.mainProgram = "scooter";
  };

  # agent-shell comes from custom-packages.nix, so the package compiles
  # against the agent-shell it runs with.
  elisp = { epkgs, agent-shell }: epkgs.trivialBuild {
    pname = "scooter";
    inherit version;
    src = "${src}/lisp";
    packageRequires = [ epkgs.magit-section epkgs.transient agent-shell ];
  };
}
