# local-common.nix
# Desktop-specific configuration overrides
{ config, lib, pkgs, ... }:

{
  services.openssh.settings = {
    PasswordAuthentication = lib.mkForce true;
    KbdInteractiveAuthentication = lib.mkForce true;
    X11Forwarding = lib.mkForce true;
  };

  networking.firewall.enable = lib.mkForce false;

  boot.supportedFilesystems = [ "ntfs" ];
}
