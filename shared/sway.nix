# hosts/local/sway.nix
# Sway window manager configuration for Home Manager
# Migrated from ~/.config/i3/config
#
# Thin aggregator: the focused modules under shared/sway/ supply the script
# derivations, the waybar settings/stylesheet, and the main sway config string.
# This file owns the single-valued home.file/home.packages assignments so the
# generated text is byte-identical to the pre-split configuration.
{ pkgs, ... }:

let
  scripts = import ./sway/scripts.nix { inherit pkgs; };
  inherit (scripts)
    workspace-script
    wallpaper-script
    lock-script
    volume-script
    record-script;

  workspaceBin = "${workspace-script}/bin/workspace.sh";
  wallpaperBin = "${wallpaper-script}/bin/wallpaper.sh";
  lockBin = "${lock-script}/bin/lock.sh";
  volumeBin = "${volume-script}/bin/volume.sh";
  recordBin = "${record-script}/bin/record.sh";

  waybar = import ./sway/waybar.nix { inherit pkgs; };

  swayConfig = import ./sway/config.nix {
    inherit pkgs workspaceBin wallpaperBin lockBin volumeBin recordBin;
  };
in
{
  home.packages = swayConfig.packages;

  home.file.".config/waybar/config".text = builtins.toJSON waybar.settings;

  home.file.".config/waybar/style.css".text = waybar.style;

  home.file.".config/mako/config".text = ''
    default-timeout=5000
  '';

  home.file.".config/sway/config".text = swayConfig.swayConfig;
}
