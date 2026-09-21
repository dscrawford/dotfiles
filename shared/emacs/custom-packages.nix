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

  # agent-shell pins exact versions of both, so these three move together.
  acp = mkEmacsPackage {
    pname = "acp";
    version = "0.15.1";
    owner = "xenodium";
    repo = "acp.el";
    rev = "v0.15.1";
    hash = "sha256-qB+phi7Frs3pHptl1xY5XzBPBIf4ukFSvAzB3uAFAyQ=";
  };

  shell-maker = mkEmacsPackage {
    pname = "shell-maker";
    version = "0.97.3";
    owner = "xenodium";
    repo = "shell-maker";
    rev = "v0.97.3";
    hash = "sha256-wH0OYeKthy+V0pWX1WNM8BEJW/gkzEdj/duJfRScS0w=";
  };

  # In the let block, not the output set, so agent-shell-workspace can depend
  # on it — attribute sets are not self-referential.
  agent-shell = mkEmacsPackage {
    pname = "agent-shell";
    version = "0.76.1";
    owner = "xenodium";
    repo = "agent-shell";
    rev = "v0.76.1";
    hash = "sha256-XwTgzVvUVueJjRrkDMaRJN9KxtlDy6KIObcQ2pojEbE=";
    packageRequires = [ shell-maker acp ];
  };
in
{
  inherit mkEmacsPackage acp shell-maker agent-shell;

  claude-code-ide = mkEmacsPackage {
    pname = "claude-code-ide";
    version = "0.2.7-unstable-2026-09-14";
    owner = "manzaltu";
    repo = "claude-code-ide.el";
    rev = "50a3d55262805d7207889ed429ff30da96fbf68b";
    hash = "sha256-u+87PjLh0Mc7C8nvDG758rdgpmjED8G/hO+FE1tj7DU=";
    packageRequires = with epkgs; [ websocket transient web-server ];
  };

  # Tab-bar workspace for agent-shell. Our fork of gveres/agent-shell-workspace,
  # carrying unmerged sidebar fixes: maker-function agent configs, selection
  # face, per-agent session titles, collapsible project groups, point stability
  # across refreshes, and crashes on tty frames -- plus the one-shot picker
  # (sidebar-toggle default), working-agent spinner, and live tool-call
  # summaries. Untagged upstream and unmerged here, so `git log` the pinned
  # rev below for the individual fixes.
  agent-shell-workspace = mkEmacsPackage {
    pname = "agent-shell-workspace";
    version = "0.1.0-unstable-2026-09-20";
    owner = "dscrawford";
    repo = "agent-shell-workspace";
    rev = "2e355fa4244120736463bf1b69f42db4181706ec";
    hash = "sha256-DNLm2xXTVRkR6YRY1tAF4uTN5Mwg9KGK6vY00lkjO0I=";
    packageRequires = [ agent-shell ];
  };
}
