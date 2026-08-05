# Gaming: Steam, Proton, gamescope, gamemode, and dconf.
# Why these knobs: docs/steam-ui-performance-research.md.
{ config, lib, pkgs, ... }:

{
  # Permanent: the 2026 ("Triton") Steam Controller needs hidapi in the Steam
  # env or the client loops on "failed firmware update".
  programs.steam.extraPackages = [ pkgs.hidapi ];

  # TEMPORARY: pin only Cemu's SDL3 to a main commit with Triton controller
  # support, which landed after the 3.4.8 release nixpkgs ships.
  # TODO: drop this overlay once `nix eval nixpkgs#sdl3.version` is past 3.4.8.
  nixpkgs.overlays = [
    (final: prev: {
      cemu = prev.cemu.override {
        SDL2 = prev.sdl2-compat.override {
          sdl3 = prev.sdl3.overrideAttrs (old: {
            version = "3.5.0-unstable-2026-06-19";
            src = final.fetchFromGitHub {
              owner = "libsdl-org";
              repo = "SDL";
              rev = "49879ba0d6997709765caa53d9029b2c3551f1eb";
              hash = "sha256-NHWjFOfeHE0GpiknnwSQ6Kqk5mxUNeUcoB+YT8gdgpo=";
            };
            # nixpkgs' sdl3 postPatch --replace-fail's a testrwlock line this
            # pinned source has since changed; that patch only runs under doCheck.
            doCheck = false;
          });
        };
      };
    })
  ];

  programs = {
    dconf.enable = true;
    gamemode.enable = true;
    gamescope = {
      enable = true;
      # Lets gamescope reach NVIDIA's Vulkan stack directly instead of via
      # XWayland — what Big Picture needs. Inert unless ENABLE_GAMESCOPE_WSI=1.
      # Deliberately NOT paired with capSysNice: on NVIDIA that fails
      # vkCreateDevice outright (ValveSoftware/gamescope#521).
      enableWsi = true;
    };
    steam = {
      enable = true;
      gamescopeSession = {
        enable = true;
        # Arms the WSI layer above; nothing else sets it.
        env.ENABLE_GAMESCOPE_WSI = "1";
        args = [
          "--expose-wayland"
          "--force-grab-cursor"
        ];
      };
      package = pkgs.steam.override {
        extraPkgs = pkgs: with pkgs; [ gamemode gamescope ];
      };
      # Select per-game in Steam → Properties → Compatibility.
      extraCompatPackages = [ (pkgs.callPackage ../../pkgs/proton-cachyos { }) ];
    };
  };
}
