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
    # Backs the local-llm-router MCP server (pkgs/local-llm-mcp).
    ollama = {
      enable = true;
      package = pkgs.ollama-cuda;
      # Explicit loopback pin so a future nixpkgs default change can't widen
      # the unauthenticated API beyond localhost.
      host = "127.0.0.1";
    };
    printing.enable = true;
    blueman.enable = true;
    flatpak.enable = true;
    gnome.gnome-keyring.enable = true;
  };

  security.pam.services.login.enableGnomeKeyring = true;
}
