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
    supportedFilesystems = [ "ntfs" ];
    kernelModules = [ "uinput" "v4l2loopback" ];
    extraModulePackages = [ config.boot.kernelPackages.v4l2loopback ];
    extraModprobeConfig = ''
      options v4l2loopback devices=1 video_nr=10 card_label="OBS-VirtualCam" exclusive_caps=1
      # Disable btusb USB autosuspend: the Intel AC9260 BT controller suspends
      # its USB link mid-stream, dropping HCI packet-completion reports
      # ("Missing completion reports ... firmware bug?") which stalls AirPods
      # A2DP audio — connects fine, then drops with no sound after a few seconds.
      options btusb enable_autosuspend=0
    '';
  };
}
