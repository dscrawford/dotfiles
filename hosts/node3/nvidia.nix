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

  # Expose GPU to containers (required for Kubernetes GPU scheduling)
  hardware.nvidia-container-toolkit.enable = true;
  virtualisation.docker.enable = true;

  # Register nvidia runtime with containerd so kubelet can schedule GPU pods
  virtualisation.containerd = {
    enable = true;
    settings = {
      plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia = {
        runtime_type = "io.containerd.runc.v2";
        options.BinaryName = "${pkgs.nvidia-container-toolkit}/bin/nvidia-container-runtime";
      };
      plugins."io.containerd.grpc.v1.cri".containerd.default_runtime_name = "nvidia";
    };
  };
}
