# shared/emacs/scooter-mode.nix
# scooter-mode (github.com/chadac-me/scooter-mode): the `scooter` bridge
# (`scooter acp`, an ACP agent for agent-shell) and its Emacs package, built
# from one pinned source so the two always match.
#
# Pinned to feat/kanban on the dscrawford fork: combined/dcraw (chadac-me#19
# plus the open PRs #20-#24: mid-session sign-in, Firefox login, answer
# delivery, sandbox path links, push race) and dscrawford#1 (kanban boards).
# Move back to chadac-me once those merge.
{ pkgs }:

let
  version = "0.1.0-unstable-2026-11-10";
  src = pkgs.fetchFromGitHub {
    owner = "dscrawford";
    repo = "scooter-mode";
    rev = "8b1536aeeda7da8ef8abe548cf0204c3cd6dc360";
    hash = "sha256-leI7xpT1MQ8rIoOURpci7pFf6Kg1fpAXyB1V8Ro+oyY=";
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
