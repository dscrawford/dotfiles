{ lib, config, pkgs, linuxPackages, ...}:
let
  unstable = import <unstable> {};
  glibc_pkgs = import (builtins.fetchTarball {
        url = "https://github.com/NixOS/nixpkgs/archive/1b7a6a6e57661d7d4e0775658930059b77ce94a4.tar.gz";
  }) {};
  home_dir = "/home/daniel";
in
{
  # Home Manager needs a bit of information about you and the paths it should
  # manage.
  home.username = "daniel";
  home.homeDirectory = "/home/daniel";

  # This value determines the Home Manager release that your configuration is
  # compatible with. This helps avoid breakage when a new Home Manager release
  # introduces backwards incompatible changes.
  #
  # You should not change this value, even if you update Home Manager. If you do
  # want to update the value, then make sure to first check the Home Manager
  # release notes.
  home.stateVersion = "23.05"; # Please read the comment before changing.
  
  # The home.packages option allows you to install Nix packages into your
  # environment.
  home.packages = with pkgs; [
    # utilities
    xclip
    protontricks
    appimagekit
    zsync
    appstream
    appimage-run
    steam
    zip
    unzip
    cachix
    simplescreenrecorder
    virtualenv
    spotify
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
  ] ++ [
    unstable.godot_4
    unstable.jetbrains.pycharm-professional
    unstable.wine
    unstable.winetricks
    unstable.lutris
    unstable.chromium
    unstable.pavucontrol
    unstable.vlc
    unstable.busybox
    unstable.neofetch
    unstable.alacritty
    unstable.discord
    glibc_pkgs.glibc
  ];
  

  # Home Manager is pretty good at managing dotfiles. The primary way to manage
  # plain files is through 'home.file'.
  home.file = {
    ".emacs.d" = {
      source = /home/daniel/.emacs.d;
      recursive = true;
    };
  };

  # You can also manage environment variables but you will have to manually
  # source
  #
  #  ~/.nix-profile/etc/profile.d/hm-session-vars.sh
  #
  # or
  #
  #  /etc/profiles/per-user/daniel/etc/profile.d/hm-session-vars.sh
  #
  # if you don't want to manage your shell through Home Manager.
  home.sessionVariables = {
    EDITOR = "emacs";
  };

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  # emacs
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
      emacsql-sqlite
    ]);
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
  };

  programs.tmux = {
    enable = true;
    extraConfig = ''
    set -g default-terminal "screen-256color"
    set-option -g status-position top
    '';
  };

  # GPG
  services.gpg-agent = {
    enable = true;
    defaultCacheTtl = 1800;
    enableSshSupport = true;
  };

  # Git
  programs.git = {
    enable = true;
    userName  = "Daniel Crawford";
    userEmail = "daniel.sc.crawford@gmail.com";
    extraConfig = {
      color = {
        ui = "auto";
        branch = true;
        diff = true;
        interactive = true;
        status = true;
        log = true;
      };
    };
  };

  # Nix flakes
  nix =  {
    package = pkgs.nix;
    settings.experimental-features = [ "nix-command" "flakes" ];
  };

}
