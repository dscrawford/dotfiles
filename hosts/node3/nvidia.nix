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
}
