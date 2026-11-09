# shared/emacs/scooter-mode.nix
# scooter-mode (github.com/chadac-me/scooter-mode): the `scooter` bridge
# (`scooter acp`, an ACP agent for agent-shell) and its Emacs package, built
# from one pinned source so the two always match.
{ pkgs }:

let
  version = "0.1.0-unstable-2026-11-04";
  src = pkgs.fetchFromGitHub {
    owner = "chadac-me";
    repo = "scooter-mode";
    rev = "1cca6f98a709bc7e3ed152de20b64ed6c414b0a9";
    hash = "sha256-e08jmXQ9ThM2CMgowB8Pl1xrcMcJ6sVAIZ5c8xVEDEI=";
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
