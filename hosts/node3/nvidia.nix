# NVIDIA GTX 1080 Ti — for GPU compute workloads in Kubernetes
{ config, lib, pkgs, ... }:
{
  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
    "nvidia-x11"
    "nvidia-settings"
    "nvidia-kernel-modules"
    "nvidia-container-toolkit"
  ];

  services.xserver.videoDrivers = [ "nvidia" ];

  hardware = {
    graphics = {
      enable = true;
      enable32Bit = true;
    };
    nvidia = {
      modesetting.enable = true;
      open = false;  # GTX 1080 Ti is not supported by the open driver
      package = config.boot.kernelPackages.nvidiaPackages.legacy_580;
      # Without this, containers lose GPU access over time
      # (FFmpeg exit 187 / "Failed to initialize NVML").
      nvidiaPersistenced = true;
      powerManagement.enable = true;
    };
    # Generates CDI specs at /var/run/cdi/. Pair with generic-cdi-plugin, not
    # NVIDIA's k8s-device-plugin, which needs FHS paths and /etc/ld.so.cache.
    nvidia-container-toolkit.enable = true;
  };

  virtualisation.docker.enable = true;

  # So kubelet can schedule GPU pods.
  virtualisation.containerd.settings.plugins."io.containerd.grpc.v1.cri" = {
    enable_cdi = lib.mkForce true;
    cdi_spec_dirs = lib.mkForce [ "/var/run/cdi" "/etc/cdi" ];
  };

  # Jellyfin subtitle burn-in: hostPath-mounted into the pod at /usr/share/fonts,
  # with Dashboard > Playback > Fallback Font set to /usr/share/fonts/custom/.
  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-cjk-sans
  ];
}
