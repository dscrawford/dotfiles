# System-level desktop configuration for the `local` host.
{ config, lib, pkgs, ... }:

{
  imports = [
    ./boot.nix
    ./nvidia.nix
    ./bluetooth.nix
    ./audio.nix
    ./priority.nix
    ./udev.nix
    ./gpu-monitor.nix
    ./services.nix
    ./desktop.nix
    ./steam.nix
  ];

  time.timeZone = "America/Los_Angeles";
  time.hardwareClockInLocalTime = true;
  i18n.defaultLocale = "en_US.UTF-8";
  console = {
    font = "Lat2-Terminus16";
    keyMap = "us";
  };

  nixpkgs.config.allowUnfree = true;
  # gemini-cli carries a removal notice (replaced by Antigravity CLI), but
  # pair.nix drives it over ACP with GEMINI_API_KEY and agent-shell has no
  # antigravity support; revisit when it does or nixpkgs drops the package.
  nixpkgs.config.problems.handlers."gemini-cli".removal = "ignore";

  environment = {
    systemPackages = with pkgs; [
      exfat
      bluez
      cudatoolkit
      gtk3
      (ffmpeg-full.override { withUnfree = true; withOpengl = true; })
      v4l-utils
      guvcview
      obs-studio
      gnome-keyring
      libsecret
      tree
      findutils
      gnugrep
      gnused
      gawk
      util-linux
      jq
      libva-utils
      # Forced onto XWayland: Qt-embedded mpv on native Wayland + NVIDIA shows
      # out-of-order frames (flash of a previous frame) on sway.
      (pkgs.symlinkJoin {
        name = "jellyfin-desktop-xcb";
        paths = [ pkgs.jellyfin-desktop ];
        buildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          wrapProgram $out/bin/jellyfin-desktop --set QT_QPA_PLATFORM xcb
        '';
      })
    ];
    variables = {
      GSETTINGS_SCHEMA_DIR = "${pkgs.gtk3}/share/gsettings-schemas/${pkgs.gtk3.name}/glib-2.0/schemas";
      XDG_CURRENT_DESKTOP = "sway";
      GTK_THEME = "Adwaita:dark";
      # Two NVIDIA vars are deliberately NOT set here (full workings in
      # docs/steam-ui-performance-research.md):
      # WLR_NO_HARDWARE_CURSORS — wlroots refuses direct scan-out on any output
      # with a software cursor, costing a full render pass per frame everywhere.
      # GBM_BACKEND — redundant on the host, and it leaked into Steam's
      # pressure-vessel container (ships only dri_gbm.so), killing CEF's dmabuf path.
      NIXOS_OZONE_WL = "1";
      __GLX_VENDOR_LIBRARY_NAME = "nvidia";
      NVD_BACKEND = "direct";
    };
    pathsToLink = [ "/libexec" ];
  };

  virtualisation.docker.enable = true;

  users.groups.bluetooth = {};
  users.users.daniel = {
    isNormalUser = true;
    extraGroups = [ "wheel" "docker" "bluetooth" "input" "video" ];
  };

  networking.hosts = {
    "192.168.0.2" = [ "node1" "api.kube" ];
    "192.168.0.4" = [ "node2" ];
  };
}
