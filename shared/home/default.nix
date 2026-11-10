# shared/home/default.nix
# Home Manager configuration (cross-platform: Linux and macOS)
{ config, lib, pkgs, username, gitUser ? null, enableSecrets ? false, claudeSkills ? {}, ... }:

let
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
  isLinux = pkgs.stdenv.hostPlatform.isLinux;
  homeDir = if isDarwin then "/Users/${username}" else "/home/${username}";
in
{
  home.username = username;
  home.homeDirectory = homeDir;
  home.stateVersion = "23.05";

  imports = [
    ../emacs
    ./packages.nix
    ./diagrams.nix
    ./skills.nix
    ./secrets.nix
    # No mcp-servers.nix: Emacs gets them from agent-shell-mcp-servers
    # (emacs/agent-shell.nix), the CLI from ~/.claude.json user scope.
    ./ollama.nix
    ./llm-routing.nix
    ./scooter.nix
    ./bash.nix
    ./tmux.nix
    ./git.nix
    ./ssh.nix
    ./kube-cert-sync.nix
    ./nix-gc.nix
    ./deploy-nodes.nix
    ./reboot-nodes.nix
  ];

  # force: replace hand-managed files on first activation. settings.json is
  # read-only under nix by design; /config and /hooks can no longer write it.
  home.file = lib.genAttrs (map (p: ".claude/${p}") [
    "settings.json"
    "output-styles/concise.md"
    "rules/common/ruflo-memory.md"
    "rules/common/ruflo-tools.md"
    "agents/test-scout.md"
    "agents/security-scout.md"
    "agents/performance-scout.md"
    "agents/comment-scout.md"
    "hooks/comment-density.sh"
    "hooks/prompt-router.sh"
    "hooks/commit-guard.sh"
    "hooks/pr-guard.sh"
    "hooks/session-guard.sh"
    "hooks/tool-output-filter.sh"
  ]) (p: {
    source = ../../claude + lib.removePrefix ".claude" p;
    force = true;
  } // lib.optionalAttrs (lib.hasSuffix ".sh" p) { executable = true; }) // {
    # Display-only .ipynb diffs. The nbstripout clean/smudge filter is NOT set
    # globally — it wipes local outputs on pull; opt in per-repo instead.
    ".config/git/attributes".text = "*.ipynb diff=ipynb\n";
    # Determinate Nix manages the daemon, so nix.settings is unavailable.
    ".config/nix/nix.conf" = lib.mkIf isDarwin {
      text = ''
        keep-outputs = true
        keep-derivations = true
      '';
    };
  };

  home.sessionPath = [
    "${homeDir}/.local/bin"
  ] ++ lib.optionals isDarwin [
    "/opt/homebrew/bin"
  ];

  home.sessionVariables = {
    EDITOR = "emacsclient";
  } // lib.optionalAttrs isDarwin {
    SHELL = "/run/current-system/sw/bin/bash";
  };

  programs.home-manager.enable = true;

  programs.direnv = {
    enable = true;
    enableBashIntegration = false;
    nix-direnv.enable = true;
    config = {
      global = {
        warn_timeout = "0";
        hide_env_diff = true;
      };
    };
    stdlib = ''
      : "''${direnv_layout_dir:=$PWD/.direnv}"
    '';
  };

  # A real ssh-agent, socket-activated for the whole login session. gpg-agent
  # used to fill this role, but importing a key into it needs a pinentry this
  # config never installed ("agent refused operation"), and there are no gpg
  # keys or signing to justify keeping it.
  services.ssh-agent = lib.mkIf isLinux {
    enable = true;
  };

  # Darwin runs Determinate Nix, which owns its own settings.
  nix = lib.mkIf isLinux {
    settings.experimental-features = [ "nix-command" "flakes" ];
  };
}
