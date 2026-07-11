# shared/emacs.nix
# Emacs configuration for Home Manager.
# The configuration is split into focused modules under ./emacs/; this file
# assembles them into a single programs.emacs block, preserving package list
# order and elisp evaluation order (both are significant).
{ config, pkgs, lib, ... }:

let
  isDarwin = pkgs.stdenv.isDarwin;
  bashPath = "${pkgs.bash}/bin/bash";

  agentShell = import ./emacs/agent-shell.nix { inherit pkgs; };

  # Each elisp module is a multiline string that carries a trailing newline.
  # Strip it so the assembled config controls blank-line separators exactly,
  # matching the original single-string layout byte-for-byte.
  chunk = s: lib.removeSuffix "\n" s;

  # Empty string entries reproduce the blank lines that separated sections in
  # the original file; sections that were directly adjacent have no "" between.
  sections = [
    (chunk (import ./emacs/ui.nix { inherit pkgs lib config; }))
    ""
    (chunk agentShell.copilotCcide)
    (chunk (import ./emacs/jupyter.nix { inherit pkgs lib config; }))
    ""
    (chunk agentShell.agentShell)
    ""
    (chunk (import ./emacs/misc.nix { inherit pkgs lib config bashPath; }))
    ""
    (chunk (import ./emacs/markdown.nix { inherit pkgs; }))
    ""
    (chunk (import ./emacs/lsp.nix { inherit pkgs lib config; }))
  ];
in
{
  programs.emacs = {
    enable = true;
    package = if isDarwin then pkgs.emacs-unstable else pkgs.emacs-pgtk;
    # elpa.gnu.org regenerated org-9.8.6.tar in place, so the hash pinned in
    # nixpkgs no longer matches; drop this once nixpkgs catches up.
    overrides = final: prev: {
      org = prev.org.overrideAttrs (old: {
        src = pkgs.fetchurl {
          url = "https://elpa.gnu.org/packages/org-9.8.6.tar";
          hash = "sha256-QyrhwAW55Y4vtgMbIjSQOkNr+8uTSmXdumi2qc8dTIE=";
        };
      });
    };
    extraPackages = epkgs: import ./emacs/packages.nix { inherit pkgs epkgs; };
    # Trailing newline matches the original ''...'' block, which ended with one.
    extraConfig = (lib.concatStringsSep "\n" sections) + "\n";
  };
}
