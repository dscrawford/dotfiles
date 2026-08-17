# System services: login manager, dbus, printing, keyring, and Flatpak
{ config, lib, pkgs, ... }:

{
  services = {
    greetd = {
      enable = true;
      # --sessions is needed because tuigreet only searches
      # /usr/share/{x,wayland}-sessions, while NixOS registers sessions (e.g.
      # Steam/gamescope) under sessionData.desktops. F3 switches session.
      settings.default_session.command =
        "${pkgs.tuigreet}/bin/tuigreet --time"
        + " --sessions ${config.services.displayManager.sessionData.desktops}/share/wayland-sessions"
        + " --cmd 'sway --unsupported-gpu'";
    };
    dbus.enable = true;
    printing.enable = true;
    blueman.enable = true;
    flatpak.enable = true;
    gnome.gnome-keyring.enable = true;
  };

  security.pam.services.login.enableGnomeKeyring = true;
}
