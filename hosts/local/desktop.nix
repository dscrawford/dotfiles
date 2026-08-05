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

  # Overlay because xdg.portal.wlr hardcodes the package (no package option).
  # Pinned to 0.8.2: 0.8.3 stalls screencasts after the first frame.
  # TODO: unpin and drop the patch once a release past 0.8.3 fixes it
  # (https://github.com/emersion/xdg-desktop-portal-wlr/pull/380).
  nixpkgs.overlays = [
    (final: prev: {
      xdg-desktop-portal-wlr = prev.xdg-desktop-portal-wlr.overrideAttrs (old: {
        version = "0.8.2";
        src = prev.fetchFromGitHub {
          owner = "emersion";
          repo = "xdg-desktop-portal-wlr";
          rev = "v0.8.2";
          hash = "sha256-HITf/hgiASWvn/z49mzS8IS1vuyXwdk1JiAOOHRSQMo=";
        };
        patches = (old.patches or []) ++ [
          ../../patches/xdg-desktop-portal-wlr-fix-duplicate-frame.patch
        ];
      });
    })
  ];
  xdg.portal = {
    enable = true;
    # programs.sway runs the portal with an explicit --config that overrides
    # ~/.config/xdg-desktop-portal-wlr; without these, screen sharing silently
    # fails for want of a chooser.
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
