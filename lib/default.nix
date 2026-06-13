# Flake builder functions, extracted from flake.nix.
# Instantiated from flake outputs with the flake inputs and `lib`.
{ nixpkgs, home-manager, sops-nix, nix-darwin, darwin-emacs, everything-claude-code, cli-anything, ... }:
let
  inherit (nixpkgs) lib;

  claudeSkills = import ./claude-skills.nix { inherit everything-claude-code cli-anything; };

  inputs = { inherit nixpkgs home-manager sops-nix nix-darwin darwin-emacs lib claudeSkills; };
in {
  inherit claudeSkills;
  mkServer = import ./mkServer.nix inputs;
  mkLocal = import ./mkLocal.nix inputs;
  mkDarwin = import ./mkDarwin.nix inputs;
}
