# local-common.nix
# Desktop-specific configuration overrides
{ config, lib, pkgs, ... }:

{
  # Desktop-friendly SSH (allow password and X11 forwarding)
  services.openssh.settings = {
    PasswordAuthentication = lib.mkForce true;
    KbdInteractiveAuthentication = lib.mkForce true;
    X11Forwarding = lib.mkForce true;
  };

  # More permissive firewall for desktop use
  networking.firewall.enable = lib.mkForce false;

  # Desktop filesystem support
  boot.supportedFilesystems = [ "ntfs" ];
}
