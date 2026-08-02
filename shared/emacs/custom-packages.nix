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

  # In the let block (not the output set) so agent-shell-workspace can depend
  # on it — attribute sets are not self-referential.
  agent-shell = mkEmacsPackage {
    pname = "agent-shell";
    version = "0.63.6";
    owner = "xenodium";
    repo = "agent-shell";
    rev = "v0.63.6";
    hash = "sha256-TiTPiOPgRRCh9o+sc9s2pWwuAwsSyPn/rAEY1MCN9jM=";
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

  # Tab-bar workspace for agent-shell: sidebar, tiling, buffer isolation.
  # Untagged upstream, so pinned to a commit.
  #
  # Points at our fork, not gveres/agent-shell-workspace, which carries three
  # fixes on fix/resolve-maker-agent-configs:
  #   - sidebar render died on `map-elt' because upstream reads
  #     `agent-shell-agent-configs' entries as plain alists, but agent-shell
  #     now defaults to maker *functions* -- the sidebar stayed empty
  #   - `agent-shell-workspace-selected' was defined but never applied, and
  #     `cursor-type' is nil, so nothing showed which agent was current
  #   - agents in one project all render the same short name, so the sidebar
  #     now shows agent-shell's `(:session :title)' under each row
  #   - the sidebar groups agents under collapsible project headers
  #   - the 2s refresh restored point by character offset and never restored
  #     window point, so the cursor wandered and appeared to vanish
  #   - the sidebar crashed on any tty frame: a terminal reports its
  #     background as the string "unspecified-bg", which is non-nil but
  #     `color-values' cannot resolve, so the colour blend signalled
  #   - README binds into `agent-shell-command-map', which has never existed
  agent-shell-workspace = mkEmacsPackage {
    pname = "agent-shell-workspace";
    version = "0.1.0-unstable-2026-08-02";
    owner = "dscrawford";
    repo = "agent-shell-workspace";
    rev = "c8de8a7f63c0eb928aa6a53e911eb05263a30271";
    hash = "sha256-BmCcvDD6guwMeEAvhFNhNBBXBYIXHqoj+VKwaywoJt4=";
    packageRequires = [ agent-shell ];
  };
}
