# shared/home.nix
# Home Manager configuration (cross-platform: Linux and macOS)
{ config, lib, pkgs, username, gitUser ? null, enableSecrets ? false, claudeSkills ? {}, ... }:

let
  isDarwin = pkgs.stdenv.isDarwin;
  isLinux = pkgs.stdenv.isLinux;
  homeDir = if isDarwin then "/Users/${username}" else "/home/${username}";
in
{
  # Basic user info
  home.username = username;
  home.homeDirectory = homeDir;
  home.stateVersion = "23.05";

  # Modular configs
  imports = [
    ./emacs.nix
    ./home/packages.nix
    ./home/diagrams.nix
    ./home/skills.nix
    ./home/secrets.nix
    # MCP servers are configured in two real places, not here:
    # Emacs sessions get them from agent-shell-mcp-servers (emacs/agent-shell.nix);
    # the claude CLI reads user scope in ~/.claude.json (`claude mcp add -s user`).
    # A previous mcp-servers.nix wrote ~/.claude/.mcp.json, which nothing reads.
    ./home/bash.nix
    ./home/tmux.nix
    ./home/git.nix
    ./home/ssh.nix
    ./home/kube-cert-sync.nix
  ];

  # Dotfiles and configuration files
  home.file = {
    # Steer agent-shell/Claude Code memory to the ruflo MCP server instead of
    # the built-in file-based memory (memory/*.md + MEMORY.md index).
    ".claude/rules/common/ruflo-memory.md".source = ../claude/rules/common/ruflo-memory.md;
    # Global gitattributes: only show .ipynb diffs stripped (display-only, never
    # rewrites files). The nbstripout clean/smudge *filter* is intentionally NOT
    # applied here — it wipes local outputs on pull/checkout. Opt a single repo
    # in with `*.ipynb filter=nbstripout` in that repo's .gitattributes.
    ".config/git/attributes".text = "*.ipynb diff=ipynb\n";
    # Darwin: user-level nix.conf (Determinate Nix manages the daemon, so nix.settings unavailable)
    ".config/nix/nix.conf" = lib.mkIf isDarwin {
      text = ''
        keep-outputs = true
        keep-derivations = true
      '';
    };
  };

  # PATH additions (replaces manual export in bashrc)
  home.sessionPath = [
    "${homeDir}/.local/bin"
  ] ++ lib.optionals isDarwin [
    "/opt/homebrew/bin"
  ];

  # Environment variables
  home.sessionVariables = {
    EDITOR = "emacsclient";
  } // lib.optionalAttrs isDarwin {
    SHELL = "/run/current-system/sw/bin/bash";
  };

  # Enable home-manager
  programs.home-manager.enable = true;

  # Direnv for development environments
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

  # GPG agent (Linux only)
  services.gpg-agent = lib.mkIf isLinux {
    enable = true;
    defaultCacheTtl = 1800;
    enableSshSupport = true;
  };

  # Nix settings (flakes support) - only on Linux, Darwin uses Determinate Nix
  nix = lib.mkIf isLinux {
    settings.experimental-features = [ "nix-command" "flakes" ];
  };
}
