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
  # Pinned to 0.8.2: the 0.8.3 release stalls screencasts after the first frame
  # (upstream release notes warn about this; PR #380 was closed unmerged).
  # TODO: Unpin and drop patch once a fixed release (> 0.8.3) lands.
  # PR: https://github.com/emersion/xdg-desktop-portal-wlr/pull/380
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
