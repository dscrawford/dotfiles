# hosts/local/home.nix
# Home Manager configuration for local desktop user
{ config, lib, pkgs, username, ... }:

let
  wallpaperDir = "/home/${username}/Pictures/DarkSpacePictures";
in
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
    feh
    
    # Python
    python3
    python311Packages.protonup-ng
    
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
    WALLPAPER_DIR = wallpaperDir;
  };

  # Enable home-manager
  programs.home-manager.enable = true;

  # X session configuration - random wallpaper on login
  xsession = {
    enable = true;
    profileExtra = ''
      # Add local bin to PATH (from your existing .xprofile)
      export PATH=$PATH:/home/${username}/.local/bin/
    '';
    initExtra = ''
      # Set a random wallpaper from wallpaperDir
      if [ -d "${wallpaperDir}" ] && [ "$(ls -A ${wallpaperDir} 2>/dev/null)" ]; then
        ${pkgs.feh}/bin/feh --bg-scale --randomize "${wallpaperDir}"/*
      fi
    '';
  };

  # Optional: Systemd service to change wallpaper periodically (every 30 minutes)
  systemd.user.services.random-wallpaper = {
    Unit = {
      Description = "Change wallpaper randomly";
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash -c 'if [ -d \"${wallpaperDir}\" ] && [ \"$(ls -A ${wallpaperDir} 2>/dev/null)\" ]; then ${pkgs.feh}/bin/feh --bg-scale --randomize \"${wallpaperDir}\"/*; fi'";
    };
  };

  systemd.user.timers.random-wallpaper = {
    Unit = {
      Description = "Change wallpaper randomly every 30 minutes";
    };
    Timer = {
      OnBootSec = "5min";
      OnUnitActiveSec = "30min";
    };
    Install = {
      WantedBy = [ "timers.target" ];
    };
  };

  # Emacs configuration
  programs.emacs = {
    enable = true;
    package = pkgs.emacs-nox;
    extraPackages = epkgs: (with epkgs; [
      nix-mode
      magit
      yaml
      yaml-mode
      markdown-mode
      ox-pandoc
      use-package
      emacsql
      dockerfile-mode
      # Clipboard integration for emacs-nox
      xclip
      # Godot development support
      gdscript-mode
      # Claude Code IDE dependencies
      websocket
      transient
      web-server
      eat
      (trivialBuild {
        pname = "claude-code-ide";
        version = "0-unstable-2025";
        src = pkgs.fetchFromGitHub {
          owner = "manzaltu";
          repo = "claude-code-ide.el";
          rev = "5f12e60c6d2d1802c8c1b7944bbdf935d5db1364";
          hash = "sha256-tivRvgfI/8XBRImE3wuZ1UD0t2dNWYscv3Aa53BmHZE=";
        };
        packageRequires = with epkgs; [ websocket transient web-server ];
      })
    ]);
    extraConfig = ''
      (setq backup-directory-alist `(("." . "~/.saves")))

      ;; Start Emacs server for emacsclient (needed by emacs-mcp-server)
      (server-start)

      ;; Claude Code IDE
      (use-package claude-code-ide
        :bind ("C-c a" . claude-code-ide-menu)
        :custom
        (claude-code-ide-terminal-backend 'eat)
        :config
        (claude-code-ide-emacs-tools-setup))
      ;; Enable clipboard integration (xclip bridges emacs-nox to system clipboard)
      (xclip-mode 1)
      (setq select-enable-clipboard t)
      (setq select-enable-primary t)

      ;; Godot file type associations
      (with-eval-after-load 'gdscript-mode
        ;; GDScript files (.gd)
        (add-to-list 'auto-mode-alist '("\\.gd\\'" . gdscript-mode))
        
        ;; Godot scene files (.tscn) - treat as conf/text mode with syntax
        (add-to-list 'auto-mode-alist '("\\.tscn\\'" . conf-mode))
        
        ;; Godot resource files (.tres) - treat as conf/text mode
        (add-to-list 'auto-mode-alist '("\\.tres\\'" . conf-mode))
        
        ;; Godot project files (.godot)
        (add-to-list 'auto-mode-alist '("\\.godot\\'" . conf-mode))
        
        ;; Godot import files (.import)
        (add-to-list 'auto-mode-alist '("\\.import\\'" . conf-mode))
        
        ;; GDScript mode configuration
        (setq gdscript-use-tab-indents nil)  ; Use spaces instead of tabs
        (setq gdscript-indent-offset 4)      ; 4 spaces per indent level
        (setq gdscript-gdformat-save-enabled nil)) ; Disable auto-format on save (optional)
    '';
  };

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
