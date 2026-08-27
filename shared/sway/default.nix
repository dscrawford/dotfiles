# shared/sway/default.nix
# Aggregates the sibling modules (scripts, waybar, config string)
# and owns the home.file/home.packages assignments.
{ pkgs, ... }:

let
  scripts = import ./scripts.nix { inherit pkgs; };
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

  waybar = import ./waybar.nix { inherit pkgs; };

  swayConfig = import ./config.nix {
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
