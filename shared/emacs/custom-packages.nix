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

  # agent-shell v0.63.6 requires exactly acp 0.13.1, which is untagged HEAD
  acp = mkEmacsPackage {
    pname = "acp";
    version = "0.13.1";
    owner = "xenodium";
    repo = "acp.el";
    rev = "a29cb161ac95f1819f34481a98666707661c5cf8";
    hash = "sha256-6uicPFgKdlFIjpuVrVOgBObnLHoMVrWGktxta4fKcFU=";
  };

  shell-maker = mkEmacsPackage {
    pname = "shell-maker";
    version = "0.93.5";
    owner = "xenodium";
    repo = "shell-maker";
    rev = "v0.93.5";
    hash = "sha256-G7hU6tm4nFau9/f8I9kn7gQBjS80XymvYdHI8OAocK0=";
  };
in
{
  inherit mkEmacsPackage acp shell-maker;

  claude-code-ide = mkEmacsPackage {
    pname = "claude-code-ide";
    version = "0.2.7-unstable-2026-07";
    owner = "manzaltu";
    repo = "claude-code-ide.el";
    rev = "1de17bbadc650962a05fd68463fdff71697ec649";
    hash = "sha256-jW0R4TqXqVIumHJB9DziqB7NPfMmIKbhsn2H1dLwT6A=";
    packageRequires = with epkgs; [ websocket transient web-server ];
  };

  agent-shell = mkEmacsPackage {
    pname = "agent-shell";
    version = "0.63.6";
    owner = "xenodium";
    repo = "agent-shell";
    rev = "v0.63.6";
    hash = "sha256-TiTPiOPgRRCh9o+sc9s2pWwuAwsSyPn/rAEY1MCN9jM=";
    packageRequires = [ shell-maker acp ];
  };
}
