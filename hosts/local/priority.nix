# hosts/local/priority.nix
# Keep heavy jobs from breaking the audio path (docs/audio-under-load-research.md).
# CPU 11 and its SMT sibling 23 are reserved for PipeWire's data loop (pinned in
# audio.nix); builds are kept off them and below everything else in weight.
{ lib, ... }:

{
  nix = {
    # batch, not idle: idle would starve a nixos-rebuild behind a game.
    daemonCPUSchedPolicy = "batch";
    daemonIOSchedClass = "idle";
    daemonIOSchedPriority = 7;
    # Default is 24 jobs x all cores; bounds the burst deploy-nodes creates.
    settings.max-jobs = 4;
  };
  systemd.services.nix-daemon.serviceConfig = {
    AllowedCPUs = "0-10,12-22";
    CPUWeight = 20;
    IOWeight = 20;
    OOMScoreAdjust = 500;
    MemoryHigh = "70%";
  };

  # Under an all-core load the audio thread wakes on a downclocked core.
  powerManagement.cpuFreqGovernor = "performance";

  # Games (gamemode already sets the performance governor); a moderate renice
  # keeps a game's threads below PipeWire's non-RT threads without pinning.
  programs.gamemode.settings.general.renice = 10;

  # Memory pressure: the 2026-08-30 OOM killer hit during a game with a 4G
  # disk swap. zram absorbs spikes in RAM; oomd kills the offending leaf
  # cgroup (a game scope) on PSI before the kernel picks something at random.
  zramSwap = {
    enable = true;
    memoryPercent = 50;
    algorithm = "zstd";
  };
  boot.kernel.sysctl = {
    "vm.swappiness" = 150;
    "vm.page-cluster" = 0;
    "vm.watermark_boost_factor" = 0;
    "vm.watermark_scale_factor" = 125;
  };
  systemd.oomd = {
    enable = true;
    enableRootSlice = true;
    enableSystemSlice = true;
    enableUserSlices = true;
    settings.OOM.DefaultMemoryPressureLimit = "60%";
  };

  # memory.low only holds if every ancestor grants it.
  systemd.slices.user.sliceConfig.MemoryLow = "512M";
  systemd.services."user@".serviceConfig.MemoryLow = "512M";
  systemd.user.slices.session.sliceConfig = {
    MemoryLow = "512M";
    CPUWeight = 1000;
    IOWeight = 1000;
  };
  systemd.user.services = lib.genAttrs [ "pipewire" "wireplumber" "pipewire-pulse" ] (_: {
    overrideStrategy = "asDropin";
    serviceConfig = {
      MemoryLow = "128M";
      CPUWeight = 1000;
      IOWeight = 1000;
      OOMScoreAdjust = -900;
      ManagedOOMPreference = "avoid";
    };
  });
}
