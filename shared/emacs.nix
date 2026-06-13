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
    (chunk (import ./emacs/lsp.nix { inherit pkgs lib config; }))
  ];
in
{
  programs.emacs = {
    enable = true;
    package = if isDarwin then pkgs.emacs-unstable else pkgs.emacs-pgtk;
    extraPackages = epkgs: import ./emacs/packages.nix { inherit pkgs epkgs; };
    # Trailing newline matches the original ''...'' block, which ended with one.
    extraConfig = (lib.concatStringsSep "\n" sections) + "\n";
  };
}
