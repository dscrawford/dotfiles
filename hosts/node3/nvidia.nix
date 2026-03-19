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

  # Stable symlink for nvidia-container-runtime — survives Nix store hash changes
  systemd.tmpfiles.rules = [
    "L+ /run/nvidia-container-runtime - - - - ${pkgs.nvidia-container-toolkit}/bin/nvidia-container-runtime"
  ];

  # Register nvidia as an opt-in containerd runtime (runc stays default)
  virtualisation.containerd = {
    enable = true;
    settings = {
      plugins."io.containerd.grpc.v1.cri" = {
        enable_cdi = true;
        cdi_spec_dirs = [ "/etc/cdi" "/var/run/cdi" ];
        containerd.runtimes.nvidia = {
          privileged_without_host_devices = false;
          runtime_type = "io.containerd.runc.v2";
          options.BinaryName = "/run/nvidia-container-runtime";
        };
      };
    };
  };

  # Ensure containerd can find nvidia-container-runtime on PATH
  systemd.services.containerd.path = [ pkgs.nvidia-container-toolkit ];
}
