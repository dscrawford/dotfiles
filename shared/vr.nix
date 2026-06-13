# shared/vr.nix
# VR support for standalone headsets (Meta Quest 3) — system-level NixOS module.
#
# Two streaming stacks are enabled; pick one per session (don't run both at once):
#
# 1. WiVRn (recommended) — standalone OpenXR runtime built on Monado.
#    SteamVR is NOT needed. WiVRn registers itself as the active OpenXR
#    runtime and routes OpenVR-only titles through its bundled
#    xrizer/OpenComposite compat layer automatically.
#    Usage:
#      - Install the WiVRn client on the Quest 3 (Meta Horizon Store, or
#        sideload the APK matching the server version from
#        https://github.com/WiVRn/WiVRn/releases — check the version with
#        `wivrn-server --version`; client and server must match).
#      - Run `wivrn-dashboard` on the desktop, pair the headset (PIN),
#        then launch games from Steam or from the dashboard itself.
#
# 2. ALVR — a SteamVR driver; use this when a game genuinely needs the real
#    SteamVR runtime. Run `alvr_dashboard`, which launches SteamVR with the
#    streaming driver registered. Install the ALVR client APK on the headset.
#
# Both connect over WiFi: headset and desktop must be on the same LAN
# (5 GHz/6 GHz WiFi for the headset, desktop ideally wired).
{ config, lib, pkgs, ... }:

{
  services.wivrn = {
    enable = true;
    openFirewall = true;     # TCP/UDP 9757
    autoStart = true;        # user service starts at login; idles until a headset connects
    # NVENC hardware encoding requires the CUDA build on NVIDIA —
    # nvidia-vaapi-driver is decode-only, so without this the fallback is
    # x264 software encoding (high latency) or the newer Vulkan video encoder.
    # Note: the CUDA build is not in the public binary cache, so the first
    # rebuild compiles WiVRn locally.
    package = pkgs.wivrn.override {
      cudaSupport = lib.elem "nvidia" config.services.xserver.videoDrivers;
    };
    steam = {
      # Puts Steam in the WiVRn service PATH so games can be launched
      # from the headset/dashboard. Use the system's (overridden) package.
      enable = config.programs.steam.enable;
      package = config.programs.steam.package;
      # Sets PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES=1 system-wide so
      # Steam's container exposes the WiVRn runtime to games.
      # Requires re-login after first rebuild.
      importOXRRuntimes = true;
    };
    # WiVRn ships sane defaults and most settings (bitrate, codec, foveation)
    # are adjustable at runtime from the dashboard — leave config empty.
  };

  # ALVR: SteamVR-native streaming, kept as the fallback path.
  programs.alvr = {
    enable = true;
    openFirewall = true;     # TCP/UDP 9943, 9944
  };
}
