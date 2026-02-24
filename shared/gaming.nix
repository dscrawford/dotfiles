# shared/gaming.nix
# Gaming packages for Home Manager
{ pkgs, ... }:

{
  home.packages = with pkgs; [
    # Gaming tools
    protontricks
    python311Packages.protonup-ng
    wine
    winetricks
    lutris
    prismlauncher
    heroic
    r2modman
    ferium

    # Game dev
    godot_4

    # Game streaming
    # sunshine  # disabled: broken in nixpkgs (boost build failure)
  ];
}
