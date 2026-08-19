# System services: login manager, dbus, printing, keyring, and Flatpak
{ config, lib, pkgs, ... }:

{
  services = {
    greetd = {
      enable = true;
      # --sessions is needed because tuigreet only searches
      # /usr/share/{x,wayland}-sessions, while NixOS registers sessions (e.g.
      # Steam/gamescope) under sessionData.desktops. F3 switches session.
      # WLR_RENDERER=vulkan: NVIDIA's GLES reports GL_RGB as its read format,
      # so GLES2 screencopy offers only 24-bit BGR888 over SHM — which
      # Chromium/Electron (Discord) rejects, killing portal screenshare.
      settings.default_session.command =
        "${pkgs.tuigreet}/bin/tuigreet --time"
        + " --sessions ${config.services.displayManager.sessionData.desktops}/share/wayland-sessions"
        + " --cmd 'env WLR_RENDERER=vulkan sway --unsupported-gpu'";
    };
    dbus.enable = true;
    printing.enable = true;
    blueman.enable = true;
    flatpak.enable = true;
    gnome.gnome-keyring.enable = true;
  };

  security.pam.services.login.enableGnomeKeyring = true;
}
