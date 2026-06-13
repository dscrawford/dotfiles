# Gaming: Steam, Proton, gamescope, gamemode, and dconf
{ config, lib, pkgs, ... }:

{
  programs = {
    dconf.enable = true;
    gamemode.enable = true;
    gamescope.enable = true;
    steam = {
      enable = true;
      gamescopeSession = {
        enable = true;
        args = [
          "--expose-wayland"
          "--force-grab-cursor"
        ];
      };
      package = pkgs.steam.override {
        extraPkgs = pkgs: with pkgs; [ gamemode gamescope ];
      };
      # CachyOS Proton, pinned to the 20260520 build (20260521 crashes with
      # NVIDIA 610.43.02). Select per-game in Steam → Properties → Compatibility.
      extraCompatPackages = [ (pkgs.callPackage ../../pkgs/proton-cachyos { }) ];
    };
  };
}
