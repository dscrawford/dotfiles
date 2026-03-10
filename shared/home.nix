# shared/home.nix
# Home Manager configuration (cross-platform: Linux and macOS)
{ config, lib, pkgs, username, gitUser ? null, enableSecrets ? false, ... }:

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

  # User packages
  home.packages = with pkgs; [
    # Fonts
    nerd-fonts.symbols-only

    # Utilities
    zip
    unzip
    cachix
    virtualenv
    docker-compose
    atool
    httpie
    yq
    gnupg
    cacert
    sops
    lynx

    # Python
    (python3.withPackages (ps: with ps; [ numpy pandas fastparquet fsspec s3fs pip black ]))
    uv
    poetry

    # Linting tools
    ruff           # Python linter
    pyright        # Python language server
    statix         # Nix linter
    nil            # Nix language server
    nixfmt         # Nix formatter

    # Development tools
    openssl
    curl
    gcc
    redis

    # Cloud & Kubernetes
    kubectl
    awscli2
    kubernetes-helm
    argo-rollouts

    # Database
    postgresql

    # IDE
    claude-code
    github-copilot-cli
    nodejs  # Provides npx for keegancsmith/emacs-mcp-server and copilot.el

    # Other
    goose-cli
  ] ++ lib.optionals isDarwin [
    docker
    docker-buildx
  ] ++ lib.optionals isLinux [
    xclip
    zsync
    appstream
    appimage-run
    simplescreenrecorder
    nghttp2
    libidn2
    rtmpdump
    libpsl
    krb5
    keyutils

    # GUI Applications (Linux)
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
    jetbrains.pycharm-oss
  ];

  # Dotfiles and configuration files
  home.file = {
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
    EDITOR = "emacsclient";
  };

  # Enable home-manager
  programs.home-manager.enable = true;

  # Modular configs
  imports = [ ./emacs.nix ];

  # Direnv for development environments
  programs.direnv = {
    enable = true;
    enableBashIntegration = true;
    nix-direnv.enable = true;
  };

  # Bash configuration
  programs.bash = {
    enable = true;
    enableCompletion = true;
    bashrcExtra = ''
      PS1='\u:\W\$ '
      export PATH=${homeDir}/.local/bin/:$PATH
      export EDITOR="emacs -nw"
      export SHELL="${pkgs.bash}/bin/bash"
    '' + lib.optionalString isDarwin ''
      export PATH=$PATH:/opt/homebrew/bin
    '' + ''

      # Set emacsclient socket name to match the current tmux pane's server
      if [ -n "$TMUX_PANE" ]; then
        export EMACS_SERVER="emacs-$(echo $TMUX_PANE | tr -d %)"
        export EDITOR="emacsclient -s $EMACS_SERVER"
      fi

      # Inside Emacs (eat), open files in a new Emacs window instead of nested instance
      if [ -n "$INSIDE_EMACS" ]; then
        emacs() {
          emacsclient -s "$EMACS_SERVER" -n --eval "(progn (split-window-right) (other-window 1) (find-file \"$(realpath "$1")\"))"
        }
      else
        alias emacs="emacs -nw"
      fi

      eval "$(direnv hook bash)"

      # Eat shell integration (directory tracking, etc.)
      [ -n "$EAT_SHELL_INTEGRATION_DIR" ] && source "$EAT_SHELL_INTEGRATION_DIR/bash"
    '';
    initExtra = ''
      if command -v tmux &> /dev/null && [ -t 0 ] && [[ ! "$TERM" =~ screen ]] && [[ ! "$TERM" =~ tmux ]] && [ -z "$TMUX" ] && [ -z "$INSIDE_EMACS" ]; then
         exec tmux -f ${homeDir}/.config/tmux/tmux.conf
      fi
    '' + lib.optionalString enableSecrets ''
      if [ -f ${config.sops.secrets.anthropic_api_key.path} ]; then
        export ANTHROPIC_API_KEY=$(cat ${config.sops.secrets.anthropic_api_key.path})
      fi
    '';
  };

  # Tmux configuration
  programs.tmux = {
    enable = true;
    shell = "${pkgs.bash}/bin/bash";
    extraConfig = ''
      set -g default-terminal "screen-256color"
      set-option -g status-position top
      set-option -g default-shell "${pkgs.bash}/bin/bash"
      set-option -g default-command "${pkgs.bash}/bin/bash"
      set-option -g automatic-rename on
      set-option -g automatic-rename-format '#{b:pane_current_path}'
    '';
  };

  # GPG agent (Linux only)
  services.gpg-agent = lib.mkIf isLinux {
    enable = true;
    defaultCacheTtl = 1800;
    enableSshSupport = true;
  };

  # Git configuration
  programs.git = {
    enable = true;
    settings = {
      user = if gitUser != null then gitUser else {
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

  # Nix settings (flakes support) - only on Linux, Darwin uses Determinate Nix
  nix = lib.mkIf isLinux {
    settings.experimental-features = [ "nix-command" "flakes" ];
  };
} // lib.optionalAttrs enableSecrets {
  # SOPS configuration for secrets management (only when enableSecrets is true)
  sops = {
    age.keyFile = "${homeDir}/.config/sops/age/keys.txt";
    defaultSopsFile = ../secrets/secrets.yaml;
    secrets.anthropic_api_key = {};
  };
}
