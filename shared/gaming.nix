# shared/gaming.nix
# Gaming packages for Home Manager
{ pkgs, ... }:

{
  home.packages = with pkgs; [
    protontricks
    python311Packages.protonup-ng
    wine
    winetricks
    lutris
    prismlauncher
    heroic
    r2modman
    ferium
    cemu

    gamescope

    godot_4

    # sunshine  # disabled: broken in nixpkgs (boost build failure)
  ];
}
