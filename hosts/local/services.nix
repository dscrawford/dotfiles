# System services: login manager, dbus, printing, keyring, and Flatpak
{ config, lib, pkgs, ... }:

{
  services = {
    greetd = {
      enable = true;
      settings.default_session.command = "${pkgs.tuigreet}/bin/tuigreet --time --cmd 'sway --unsupported-gpu'";
    };
    dbus.enable = true;
    printing.enable = true;
    blueman.enable = true;
    flatpak.enable = true;
    gnome.gnome-keyring.enable = true;
  };

  security.pam.services.login.enableGnomeKeyring = true;
}
