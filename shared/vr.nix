# shared/vr.nix
# VR streaming for the Quest 3. Two stacks; run only one at a time.
# WiVRn (`wivrn-dashboard`) is the default — standalone OpenXR, no SteamVR.
# Its Quest client APK version must match `wivrn-server --version`.
# ALVR (`alvr_dashboard`) is the fallback for games needing real SteamVR.
{ config, lib, pkgs, ... }:

{
  services.wivrn = {
    enable = true;
    openFirewall = true;     # TCP/UDP 9757
    autoStart = true;
    # NVENC needs the CUDA build (nvidia-vaapi-driver is decode-only); without
    # it encoding falls back to x264. Not cached, so it compiles locally.
    package = pkgs.wivrn.override {
      cudaSupport = lib.elem "nvidia" config.services.xserver.videoDrivers;
    };
    steam = {
      enable = config.programs.steam.enable;
      package = config.programs.steam.package;
      # PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES=1, so Steam's container exposes
      # the WiVRn runtime to games. Needs a re-login after the first rebuild.
      importOXRRuntimes = true;
    };
    # Bitrate/codec/foveation are runtime dashboard settings — no config here.
  };

  programs.alvr = {
    enable = true;
    openFirewall = true;     # TCP/UDP 9943, 9944
  };
}
