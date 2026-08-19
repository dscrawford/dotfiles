# shared/emacs.nix
# Assembles the modules under ./emacs/ into one programs.emacs block.
# Package-list order and elisp evaluation order are both significant.
{ config, pkgs, lib, ... }:

let
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
  bashPath = "${pkgs.bash}/bin/bash";

  agentShell = import ./emacs/agent-shell.nix { inherit pkgs; };

  # Strip each module's trailing newline so blank-line separators are controlled
  # here, by the "" entries in `sections'.
  chunk = s: lib.removeSuffix "\n" s;

  # Must stay ahead of every section, not be a reorderable entry in `sections':
  # my/guard only expands for forms following its definition in the same file.
  prologue = chunk (import ./emacs/guard.nix { inherit pkgs lib config; });

  sections = [
    (chunk (import ./emacs/ui.nix { inherit pkgs lib config; }))
    ""
    (chunk agentShell.claudeCodeIde)
    (chunk (import ./emacs/python.nix { inherit pkgs lib config; }))
    ""
    (chunk agentShell.agentShell)
    ""
    (chunk (import ./emacs/pair.nix { }))
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
    extraConfig = prologue + "\n\n" + (lib.concatStringsSep "\n" sections) + "\n";
  };
}
