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
      # Keep GPU initialized — prevents containers from losing GPU access
      # over time (FFmpeg exit code 187 / "Failed to initialize NVML")
      nvidiaPersistenced = true;
      powerManagement.enable = true;
    };
    # Expose GPU to containers via CDI (Container Device Interface)
    # NixOS generates CDI specs at /var/run/cdi/ via nvidia-container-toolkit.
    # Use generic-cdi-plugin (not NVIDIA's k8s-device-plugin) since it reads
    # CDI specs directly without needing FHS paths or /etc/ld.so.cache.
    nvidia-container-toolkit.enable = true;
  };

  virtualisation.docker.enable = true;

  # Enable CDI in containerd so kubelet can schedule GPU pods
  virtualisation.containerd.settings.plugins."io.containerd.grpc.v1.cri" = {
    enable_cdi = lib.mkForce true;
    cdi_spec_dirs = lib.mkForce [ "/var/run/cdi" "/etc/cdi" ];
  };

  # Udev rule: ensure /dev/nvidia* device nodes are always created on boot.
  # Without this, containers can intermittently fail to access the GPU.
  services.udev.extraRules = ''
    ACTION=="add", DEVPATH=="/bus/pci/drivers/nvidia", RUN+="${lib.getExe' config.hardware.nvidia.package.bin "nvidia-modprobe"} -c 0 -u"
  '';

  # Fonts for Jellyfin subtitle burn-in (ASS/SSA).
  # Mounted into the Jellyfin pod via hostPath at /usr/share/fonts.
  # Set Jellyfin Dashboard > Playback > Fallback Font to /usr/share/fonts/custom/.
  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-cjk-sans
  ];
}
