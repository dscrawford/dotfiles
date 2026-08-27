# shared/emacs/default.nix
# Assembles the sibling modules into one programs.emacs block.
# Package-list order and elisp evaluation order are both significant.
{ config, pkgs, lib, ... }:

let
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
  bashPath = "${pkgs.bash}/bin/bash";

  agentShell = import ./agent-shell.nix { inherit pkgs lib config; };

  # Strip each module's trailing newline so blank-line separators are controlled
  # here, by the "" entries in `sections'.
  chunk = s: lib.removeSuffix "\n" s;

  # Must stay ahead of every section, not be a reorderable entry in `sections':
  # my/guard only expands for forms following its definition in the same file.
  prologue = chunk (import ./guard.nix { });

  sections = [
    (chunk (import ./ui.nix { }))
    ""
    (chunk agentShell.claudeCodeIde)
    (chunk (import ./python.nix { }))
    ""
    (chunk agentShell.agentShell)
    ""
    (chunk (import ./pair.nix { }))
    ""
    (chunk (import ./misc.nix { inherit pkgs bashPath; }))
    ""
    (chunk (import ./markdown.nix { inherit pkgs; }))
    ""
    (chunk (import ./lsp.nix { }))
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
    extraPackages = epkgs: import ./packages.nix { inherit pkgs epkgs; };
    extraConfig = prologue + "\n\n" + (lib.concatStringsSep "\n" sections) + "\n";
  };
}
