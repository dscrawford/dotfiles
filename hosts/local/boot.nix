# Boot loader, kernel modules, and modprobe configuration
{ config, lib, pkgs, ... }:

{
  boot = {
    loader = {
      efi = {
        canTouchEfiVariables = true;
        efiSysMountPoint = "/boot";
      };
      grub = {
        enable = true;
        device = "nodev";
        useOSProber = true;
        efiSupport = true;
        gfxmodeEfi = "1280x720";
      };
    };
    kernelModules = [ "uinput" "v4l2loopback" ];
    extraModulePackages = [ config.boot.kernelPackages.v4l2loopback ];
    extraModprobeConfig = ''
      options v4l2loopback devices=1 video_nr=10 card_label="OBS-VirtualCam" exclusive_caps=1
      # The Intel AC9260 suspends its USB link mid-stream, stalling AirPods A2DP
      # a few seconds in: "Missing completion reports ... firmware bug?".
      options btusb enable_autosuspend=0
    '';
  };
}
