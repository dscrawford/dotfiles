# Sway compositor and XDG desktop portals
{ config, lib, pkgs, ... }:

{
  programs.sway = {
    enable = true;
    wrapperFeatures.gtk = true;
    extraPackages = with pkgs; [
      swaylock
      swayidle
      wmenu
      waybar
      foot
      nwg-displays
      wl-clipboard
      slurp
      grim
      wf-recorder
      mako
      libnotify
    ];
  };

  xdg.portal = {
    enable = true;
    wlr.enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    # programs.sway runs the portal with an explicit --config that overrides
    # ~/.config/xdg-desktop-portal-wlr; without these, screen sharing silently
    # fails for want of a chooser.
    wlr.settings.screencast = {
      max_fps = 60;
      chooser_type = "simple";
      chooser_cmd = "${pkgs.slurp}/bin/slurp -f %o -or";
    };
    # wlr implements ScreenCast only; gtk must stay as the fallback or
    # FileChooser/Settings/Notification are left with no backend at all.
    config = lib.mkForce {
      sway = {
        default = [ "wlr" "gtk" ];
        "org.freedesktop.impl.portal.ScreenCast" = [ "wlr" ];
      };
    };
  };
}
