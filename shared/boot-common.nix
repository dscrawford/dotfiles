{ ... }:
{
  boot.loader.grub.configurationLimit = 5;
  boot.loader.systemd-boot.configurationLimit = 5;

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 7d";
  };
}
