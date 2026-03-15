# NVIDIA GTX 1080 Ti — for GPU compute workloads in Kubernetes
{ config, lib, pkgs, ... }:
{
  nixpkgs.config.allowUnfree = true;
  hardware.graphics.enable = true;
  hardware.graphics.enable32Bit = true;

  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia = {
    modesetting.enable = true;
    open = false;  # GTX 1080 Ti is not supported by the open driver
    package = config.boot.kernelPackages.nvidiaPackages.production;
  };

  # Expose GPU to containers (required for Kubernetes GPU scheduling)
  hardware.nvidia-container-toolkit.enable = true;
  virtualisation.docker = {
    enable = true;
    enableNvidia = true;
  };
}
