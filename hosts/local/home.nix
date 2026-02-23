# hosts/local/home.nix
# Home Manager configuration for local desktop user
{ config, lib, pkgs, username, ... }:

{
  # Basic user info
  home.username = username;
  home.homeDirectory = "/home/${username}";
  home.stateVersion = "23.05";

  # User packages
  home.packages = with pkgs; [
    # Utilities
    xclip
    protontricks
    zsync
    appstream
    appimage-run
    zip
    unzip
    cachix
    simplescreenrecorder
    virtualenv
    docker-compose
    # Python
    python3
    python311Packages.protonup-ng
    
    # Linting tools
    ruff           # Python linter
    statix         # Nix linter
    nil            # Nix language server

    # Development tools
    openssl
    nghttp2
    libidn2
    rtmpdump
    libpsl
    curl
    krb5
    keyutils
    kubectl
    
    # Applications
    firefox
    chromium
    brave
    spotify
    gimp
    vlc
    pavucontrol
    alacritty
    vesktop
    discord
    neofetch
    
    # Gaming
    wine
    winetricks
    lutris
    prismlauncher
    heroic
    r2modman
    ferium
    
    # IDE
    jetbrains.pycharm-oss  # Open source version (formerly pycharm-community)
    claude-code
    nodejs  # Provides npx for keegancsmith/emacs-mcp-server
    
    # Game dev
    godot_4
    
    # Other
    sunshine
    goose-cli
  ];

  # Dotfiles and configuration files
  # Note: If you want to manage .emacs.d, you can either:
  # 1. Copy it to this repo and reference it: source = ./emacs.d;
  # 2. Manage it separately outside of home-manager
  # 3. Use impure evaluation: nix build --impure
  # For now, we'll let you manage .emacs.d manually
  home.file = {
    # ".emacs.d" = {
    #   source = ./emacs.d;  # Create hosts/local/emacs.d/ directory
    #   recursive = true;
    # };

    # MCP server config for Claude Code (keegancsmith/emacs-mcp-server)
    ".claude/.mcp.json".text = builtins.toJSON {
      mcpServers = {
        emacs-mcp = {
          command = "npx";
          args = [ "-y" "@keegancsmith/emacs-mcp-server" ];
        };
      };
    };
  };

  # Environment variables
  home.sessionVariables = {
    EDITOR = "emacs -nw";
  };

  # Enable home-manager
  programs.home-manager.enable = true;

  # Modular configs: Emacs editor, Sway window manager
  imports = [ ./emacs.nix ./sway.nix ];

  # Direnv for development environments
  programs.direnv = {
    enable = true;
    enableBashIntegration = true;
    nix-direnv.enable = true;
  };

  # Bash configuration
  programs.bash = {
    enable = true;
    bashrcExtra = ''
      export PATH=/home/${username}/.local/bin/:$PATH

      if command -v tmux &> /dev/null && [ -n "$PS1" ] && [[ ! "$TERM" =~ screen ]] && [[ ! "$TERM" =~ tmux ]] && [ -z "$TMUX" ]; then
         exec tmux -f /home/${username}/.config/tmux/tmux.conf
      fi

      eval "$(direnv hook bash)"
    '';
    initExtra = ''
      if [ -f ${config.sops.secrets.anthropic_api_key.path} ]; then
        export ANTHROPIC_API_KEY=$(cat ${config.sops.secrets.anthropic_api_key.path})
      fi
    '';
  };

  # Tmux configuration
  programs.tmux = {
    enable = true;
    extraConfig = ''
      set -g default-terminal "screen-256color"
      set-option -g status-position top
    '';
  };

  # GPG agent
  services.gpg-agent = {
    enable = true;
    defaultCacheTtl = 1800;
    enableSshSupport = true;
  };

  # Git configuration
  programs.git = {
    enable = true;
    settings = {
      user = {
        name = "Daniel Crawford";
        email = "daniel.sc.crawford@gmail.com";
      };
      color = {
        ui = "auto";
        branch = true;
        diff = true;
        interactive = true;
        status = true;
        log = true;
      };
      core = {
        pager = "cat";
      };
    };
  };

  # Nix settings (flakes support)
  # Note: nix.package is set by system configuration, don't override here
  nix = {
    settings.experimental-features = [ "nix-command" "flakes" ];
  };

  # SOPS configuration for secrets management
  sops = {
    age.keyFile = "/home/daniel/.config/sops/age/keys.txt";
    defaultSopsFile = ../../secrets/secrets.yaml;
    secrets.anthropic_api_key = {};
  };
}
