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
    ./copilot.nix
    ./bash.nix
    ./tmux.nix
    ./git.nix
    ./ssh.nix
    ./kube-cert-sync.nix
    ./deploy-nodes.nix
  ];

  home.file = {
    # Steer agent-shell/Claude Code memory to the ruflo MCP server instead of
    # the built-in file-based memory (memory/*.md + MEMORY.md index).
    ".claude/rules/common/ruflo-memory.md".source = ../../claude/rules/common/ruflo-memory.md;
    # Rein in comment-heavy generated code across Claude Code and agent-shell.
    ".claude/rules/common/comment-policy.md".source = ../../claude/rules/common/comment-policy.md;
    # Read-only under nix by design; /config and /hooks can no longer write it.
    # force: replace the pre-existing hand-managed file on first activation.
    ".claude/settings.json" = {
      source = ../../claude/settings.json;
      force = true;
    };
    ".claude/output-styles/concise.md".source = ../../claude/output-styles/concise.md;
    ".claude/hooks/prompt-router.sh" = {
      source = ../../claude/hooks/prompt-router.sh;
      executable = true;
      force = true;
    };
    ".claude/hooks/commit-guard.sh" = {
      source = ../../claude/hooks/commit-guard.sh;
      executable = true;
      force = true;
    };
    ".claude/hooks/tool-output-filter.sh" = {
      source = ../../claude/hooks/tool-output-filter.sh;
      executable = true;
      force = true;
    };
    # Read-only advisors spawned alongside feature work; no Edit/Write in
    # their tools, so the main agent stays the single writer.
    ".claude/agents/test-scout.md" = {
      source = ../../claude/agents/test-scout.md;
      force = true;
    };
    ".claude/agents/security-scout.md" = {
      source = ../../claude/agents/security-scout.md;
      force = true;
    };
    ".claude/agents/performance-scout.md" = {
      source = ../../claude/agents/performance-scout.md;
      force = true;
    };
    ".claude/agents/comment-scout.md" = {
      source = ../../claude/agents/comment-scout.md;
      force = true;
    };
    ".claude/rules/common/ruflo-tools.md".source = ../../claude/rules/common/ruflo-tools.md;
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

  services.gpg-agent = lib.mkIf isLinux {
    enable = true;
    defaultCacheTtl = 1800;
    enableSshSupport = true;
  };

  # Darwin runs Determinate Nix, which owns its own settings.
  nix = lib.mkIf isLinux {
    settings.experimental-features = [ "nix-command" "flakes" ];
  };
}
