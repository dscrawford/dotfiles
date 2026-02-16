{ ... }:
{
  # Automatically clean old boot entries
  # Keeps only the last 5 generations to save disk space
  boot.loader.grub.configurationLimit = 5;
  boot.loader.systemd-boot.configurationLimit = 5;  # Also set for systemd-boot systems

  # Automatic garbage collection
  # Runs weekly and removes generations older than 7 days
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 7d";
  };
}
