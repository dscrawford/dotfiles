# Desktop configuration for local machine
{ config, lib, pkgs, ... }:

{
  imports = [
    ./boot.nix
    ./nvidia.nix
    ./bluetooth.nix
    ./audio.nix
    ./udev.nix
    ./gpu-monitor.nix
    ./services.nix
    ./desktop.nix
    ./steam.nix
  ];

  # === Locale ===
  time.timeZone = "America/Los_Angeles";
  time.hardwareClockInLocalTime = true;
  i18n.defaultLocale = "en_US.UTF-8";
  console = {
    font = "Lat2-Terminus16";
    keyMap = "us";
  };

  # === Nixpkgs ===
  nixpkgs.config.allowUnfree = true;

  # === Environment ===
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
      # Upstream renamed "Jellyfin Media Player" -> "Jellyfin Desktop" (v2.0.0);
      # nixpkgs aliased jellyfin-media-player -> jellyfin-desktop on 2025-12-14.
      # Use the canonical name so we don't depend on the deprecated alias.
      # Run under XWayland: Qt-embedded mpv on native Wayland + NVIDIA shows
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
      # NVIDIA Wayland workarounds
      WLR_NO_HARDWARE_CURSORS = "1";
      NIXOS_OZONE_WL = "1";       # Electron/Chromium apps use Wayland
      GBM_BACKEND = "nvidia-drm";
      __GLX_VENDOR_LIBRARY_NAME = "nvidia";
      NVD_BACKEND = "direct";             # nvidia-vaapi-driver direct backend
    };
    pathsToLink = [ "/libexec" ];
  };

  # === Virtualization ===
  virtualisation.docker.enable = true;

  # === Users ===
  users.groups.bluetooth = {};
  users.users.daniel = {
    isNormalUser = true;
    extraGroups = [ "wheel" "docker" "bluetooth" "input" "video" ];
  };

  # === Networking ===
  networking.hosts = {
    "192.168.0.2" = [ "node1" "api.kube" ];
    "192.168.0.4" = [ "node2" ];
  };
}
