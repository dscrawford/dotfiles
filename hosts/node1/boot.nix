{ ... }:
{
  imports = [ ../../shared/server-boot.nix ];
  boot.loader.grub.device = "/dev/disk/by-id/wwn-0x600508b1001cc4b250515aeb16212483";
}
