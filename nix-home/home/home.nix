{ lib, config, pkgs, linuxPackages, ...}:
let
  unstable = import <unstable> {};
  home_dir = "/home/daniel";
in
{
  imports = [
    (builtins.fetchTarball {
      url = "https://github.com/Mic92/sops-nix/archive/master.tar.gz";
    } + "/modules/home-manager/sops.nix")
  ];
  
  home.username = "daniel";
  home.homeDirectory = "/home/daniel";
  home.stateVersion = "23.05";
  
  home.packages = with pkgs; [
    # utilities
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
    spotify
    gimp
    docker-compose
    feh
    appimage-run
    # python packages
    python3
    python311Packages.protonup-ng
    # libraries
    openssl
    nghttp2
    libidn2
    rtmpdump
    libpsl
    curl
    krb5
    keyutils
    glibc
    busybox
    godot_4
    sunshine
    prismlauncher
  ] ++ [
    unstable.firefox
    unstable.jetbrains.pycharm
    unstable.wine
    unstable.winetricks
    unstable.lutris
    unstable.chromium
    unstable.pavucontrol
    unstable.vlc
    unstable.neofetch
    unstable.alacritty
    unstable.vesktop
    unstable.wget
    unstable.brave
    unstable.r2modman
    unstable.ferium
    unstable.discord
    unstable.kubectl
    unstable.goose-cli
    shadps4
    heroic
  ];
  
  home.file = {
    ".emacs.d" = {
      source = /home/daniel/.emacs.d;
      recursive = true;
    };
  };

  # Combine both sessionVariables into one
  home.sessionVariables = {
    EDITOR = "emacs";
  };

  programs.home-manager.enable = true;

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
    ]);
    extraConfig = ''
    (setq backup-directory-alist `(("." . "~/.saves")))
    ;; Enable clipboard integration
    (setq select-enable-clipboard t)
    (setq select-enable-primary t)
    '';
  };

  programs.direnv = {
    enable = true;
    enableBashIntegration = true;
    nix-direnv.enable = true;
  };

  programs.bash = {
    enable = true;
    bashrcExtra = ''
    export PATH=/home/daniel/.local/bin/:$PATH

    if command -v tmux &> /dev/null && [ -n "$PS1" ] && [[ ! "$TERM" =~ screen ]] && [[ ! "$TERM" =~ tmux ]] && [ -z "$TMUX" ]; then
       exec tmux -f ${home_dir}/.config/tmux/tmux.conf
    fi

    eval "$(direnv hook bash)"
    '';
    # Add the API key loading here
    initExtra = ''
      if [ -f ${config.sops.secrets.anthropic_api_key.path} ]; then
        export ANTHROPIC_API_KEY=$(cat ${config.sops.secrets.anthropic_api_key.path})
      fi
    '';
  };

  programs.tmux = {
    enable = true;
    extraConfig = ''
    set -g default-terminal "screen-256color"
    set-option -g status-position top
    '';
  };

  services.gpg-agent = {
    enable = true;
    defaultCacheTtl = 1800;
    enableSshSupport = true;
  };

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

  nix = {
    package = pkgs.nix;
    settings.experimental-features = [ "nix-command" "flakes" ];
  };

  # SOPS configuration
  sops = {
    age.keyFile = "/home/daniel/.config/sops/age/keys.txt";
    defaultSopsFile = ./secrets.yaml;
    
    secrets.anthropic_api_key = { };
  };
}
