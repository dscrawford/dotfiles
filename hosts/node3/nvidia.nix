# NVIDIA GTX 1080 Ti — for GPU compute workloads in Kubernetes
{ config, lib, pkgs, ... }:
{
  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
    "nvidia-x11"
    "nvidia-settings"
    "nvidia-container-toolkit"
  ];
  hardware.graphics.enable = true;
  hardware.graphics.enable32Bit = true;

  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia = {
    modesetting.enable = true;
    open = false;  # GTX 1080 Ti is not supported by the open driver
    package = config.boot.kernelPackages.nvidiaPackages.production;
  };

  # Expose GPU to containers via CDI (Container Device Interface)
  # The nvidia-container-toolkit module generates CDI specs at /var/run/cdi/
  # and containerd injects GPU devices into pods that request them.
  # No legacy nvidia-container-runtime wrapper needed.
  hardware.nvidia-container-toolkit.enable = true;
  virtualisation.docker.enable = true;

  # Enable CDI in containerd so kubelet can schedule GPU pods
  virtualisation.containerd = {
    enable = true;
    settings = {
      plugins."io.containerd.grpc.v1.cri" = {
        enable_cdi = lib.mkForce true;
        cdi_spec_dirs = lib.mkForce [ "/etc/cdi" "/var/run/cdi" ];
      };
    };
  };
}
