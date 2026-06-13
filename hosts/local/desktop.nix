# Sway compositor and XDG desktop portals
{ config, lib, pkgs, ... }:

{
  programs.sway = {
    enable = true;
    wrapperFeatures.gtk = true;
    extraPackages = with pkgs; [
      swaylock       # screen locker (replaces i3lock)
      swayidle       # idle management
      wmenu          # Wayland-native launcher (replaces dmenu)
      waybar         # status bar
      foot           # Wayland-native terminal
      nwg-displays   # GUI monitor configuration
      wl-clipboard   # Wayland clipboard (replaces xclip)
      slurp          # Region/output selector for screen sharing
      grim           # Screenshot tool for Wayland
      wf-recorder    # Screen recording for Wayland
      mako           # Notification daemon for Wayland
      libnotify      # notify-send command
    ];
  };

  # The xdg.portal.wlr module hardcodes pkgs.xdg-desktop-portal-wlr (no package
  # option), so the duplicate-frame patch must be applied via overlay.
  # TODO: Remove patch once xdg-desktop-portal-wlr > 0.8.2 is released
  # PR: https://github.com/emersion/xdg-desktop-portal-wlr/pull/380
  nixpkgs.overlays = [
    (final: prev: {
      xdg-desktop-portal-wlr = prev.xdg-desktop-portal-wlr.overrideAttrs (old: {
        patches = (old.patches or []) ++ [
          ../../patches/xdg-desktop-portal-wlr-fix-duplicate-frame.patch
        ];
      });
    })
  ];
  xdg.portal = {
    enable = true;
    # nixpkgs' programs.sway module force-enables xdg.portal.wlr, which runs the
    # portal with an explicit --config that OVERRIDES ~/.config/xdg-desktop-portal-wlr.
    # Without these settings the generated config is empty: no screencast chooser
    # is found and screen sharing silently fails.
    wlr.settings.screencast = {
      max_fps = 60;
      chooser_type = "simple";
      chooser_cmd = "${pkgs.slurp}/bin/slurp -f %o -or";
    };
    config = lib.mkForce {
      sway = {
        default = [ "wlr" ];
      };
    };
  };
}
