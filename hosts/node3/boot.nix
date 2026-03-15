# X399 boards support UEFI — using systemd-boot instead of GRUB
# If you need legacy BIOS boot, switch to grub like node1/node2
{ ... }:
{
  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };
}
