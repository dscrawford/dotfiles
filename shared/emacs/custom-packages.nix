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

  # agent-shell requires exactly acp 0.13.1, which is untagged; pinned past the
  # 0.13.1 tag point to pick up "Clear out subscriptions when shutting down".
  acp = mkEmacsPackage {
    pname = "acp";
    version = "0.13.1";
    owner = "xenodium";
    repo = "acp.el";
    rev = "7d5c16ebcf2af86aa0f14ad9ae0ce45df4e8c8a5";
    hash = "sha256-fjQwxSim8nfD76xcknErYVqPQqjXqI3b9amEV0GOfKU=";
  };

  shell-maker = mkEmacsPackage {
    pname = "shell-maker";
    version = "0.95.3";
    owner = "xenodium";
    repo = "shell-maker";
    rev = "v0.95.3";
    hash = "sha256-KC/dE35hdQPJ6fgmp5nVlDtRjACzTnTIeh7rluORVYA=";
  };

  # In the let block, not the output set, so agent-shell-workspace can depend
  # on it — attribute sets are not self-referential.
  agent-shell = mkEmacsPackage {
    pname = "agent-shell";
    version = "0.69.2";
    owner = "xenodium";
    repo = "agent-shell";
    rev = "v0.69.2";
    hash = "sha256-b3JiSCZSV9DyYSRfqtIQ1CZ3JRgWjNYEerfUQF6C414=";
    packageRequires = [ shell-maker acp ];
  };
in
{
  inherit mkEmacsPackage acp shell-maker agent-shell;

  claude-code-ide = mkEmacsPackage {
    pname = "claude-code-ide";
    version = "0.2.7-unstable-2026-07";
    owner = "manzaltu";
    repo = "claude-code-ide.el";
    rev = "1de17bbadc650962a05fd68463fdff71697ec649";
    hash = "sha256-jW0R4TqXqVIumHJB9DziqB7NPfMmIKbhsn2H1dLwT6A=";
    packageRequires = with epkgs; [ websocket transient web-server ];
  };

  # Tab-bar workspace for agent-shell. Our fork of gveres/agent-shell-workspace,
  # carrying unmerged sidebar fixes: maker-function agent configs, selection
  # face, per-agent session titles, collapsible project groups, point stability
  # across refreshes, and crashes on tty frames. Untagged upstream and unmerged
  # here, so `git log` the pinned rev below for the individual fixes.
  agent-shell-workspace = mkEmacsPackage {
    pname = "agent-shell-workspace";
    version = "0.1.0-unstable-2026-08-02";
    owner = "dscrawford";
    repo = "agent-shell-workspace";
    rev = "42e75a067acc1da3ffd561a39f8ed2987dcce4db";
    hash = "sha256-cA/GfnU9S8rbEpZEfEtHY75mZ4mT3G7UK6kvaN7pG3g=";
    packageRequires = [ agent-shell ];
  };
}
