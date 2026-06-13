# shared/emacs/custom-packages.nix
# Helper for building Emacs packages from GitHub via trivialBuild.
{ pkgs, epkgs }:

let
  mkEmacsPackage =
    { pname, version, owner, repo, rev, hash, packageRequires ? [ ] }:
    epkgs.trivialBuild {
      inherit pname version packageRequires;
      src = pkgs.fetchFromGitHub { inherit owner repo rev hash; };
    };
in
{
  inherit mkEmacsPackage;

  ultra-scroll = mkEmacsPackage {
    pname = "ultra-scroll";
    version = "0-unstable-2025";
    owner = "jdtsmith";
    repo = "ultra-scroll";
    rev = "08758c6772c5fbce54fb74fb5cce080b6425c6ce";
    hash = "sha256-hKgwjs4qZikbvHKjWIJFlkI/4LXR6qovCoTBM5miVr8=";
  };

  claude-code-ide = mkEmacsPackage {
    pname = "claude-code-ide";
    version = "0-unstable-2025";
    owner = "manzaltu";
    repo = "claude-code-ide.el";
    rev = "56db02ee386d009ddb8b1482310f1f9beeefb810";
    hash = "sha256-qH1QnG5G+0UiH/v0KaS7oSpQZY+BkUMZvrjbx6kyFhg=";
    packageRequires = with epkgs; [ websocket transient web-server ];
  };

  acp = mkEmacsPackage {
    pname = "acp";
    version = "0.12.2";
    owner = "xenodium";
    repo = "acp.el";
    rev = "v0.12.2";
    hash = "sha256-gtRoM8hdB+opnIPn49KkHwdWoR8qbt9sPdg9TvzQtv8=";
  };

  shell-maker = mkEmacsPackage {
    pname = "shell-maker";
    version = "0-unstable-2025";
    owner = "xenodium";
    repo = "shell-maker";
    rev = "e8bdf6dca18f39d592728e8440118d9f57092e65";
    hash = "sha256-tmhZ9WApwSjzAlXUcZy+aMpW/07bTpIaaDMCALXtyzI=";
  };

  agent-shell = mkEmacsPackage {
    pname = "agent-shell";
    version = "0-unstable-2025";
    owner = "xenodium";
    repo = "agent-shell";
    rev = "89bd6e136a08e1527dd630e4573639c838fd7e22";
    hash = "sha256-ZSxCxiA+DH0tvIrGVhOUGOgrn1k0ilNr9WL4n3Aox+8=";
    packageRequires = with epkgs; [ shell-maker acp ];
  };
}
