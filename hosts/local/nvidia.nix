# Graphics stack and NVIDIA proprietary driver
{ config, lib, pkgs, ... }:

{
  hardware = {
    graphics = {
      enable = true;
      enable32Bit = true;
      extraPackages = with pkgs; [
        nvidia-vaapi-driver
      ];
    };
    nvidia = {
      modesetting.enable = true;
      powerManagement.enable = false;
      open = false;
      nvidiaSettings = true;
      # Tracks the new-feature branch (610.43.03), not a frozen version — a
      # flake update can move it. Drop to .production if 610.x misbehaves.
      package = config.boot.kernelPackages.nvidiaPackages.latest;
    };
  };

  services.xserver.videoDrivers = [ "nvidia" ];
}
