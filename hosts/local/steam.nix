# Gaming: Steam, Proton, gamescope, gamemode, and dconf
{ config, lib, pkgs, ... }:

{
  # The 2026 ("Triton") Steam Controller needs hidapi in the Steam env so the
  # client can talk to the controller (otherwise repeated "failed firmware
  # update" errors). See https://wiki.nixos.org/wiki/Steam
  # NOTE: permanent requirement for that controller, not a temporary workaround.
  programs.steam.extraPackages = [ pkgs.hidapi ];

  # --- TEMPORARY: new Steam Controller (Triton) support for Cemu ---------------
  # Cemu's controller input runs on SDL2 → sdl2-compat → SDL3. Native support for
  # the 2026 Steam Controller landed in SDL3 *after* the 3.4.8 release nixpkgs
  # currently ships (Triton HIDAPI commits, 2026-05-27/28), so the stock Cemu can
  # only see Steam Input's virtual pad — unreliable for non-Steam SDL apps. Pin
  # ONLY Cemu's SDL3 to a main commit that includes Triton support.
  # TODO: Remove this whole overlay once nixpkgs' sdl3 is past 3.4.8 with the new
  #       Steam Controller support — check `nix eval nixpkgs#sdl3.version`. Then a
  #       plain rebuild restores stock Cemu, which by then reads it natively.
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
          });
        };
      };
    })
  ];
  # --- END TEMPORARY ----------------------------------------------------------

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
