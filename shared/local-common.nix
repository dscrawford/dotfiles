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

  # Router (192.168.0.1) DHCP hands out its own DNS, whose forwarder is
  # unreliable — bypass it with public resolvers.
  networking.nameservers = [ "1.1.1.1" "9.9.9.9" ];
  networking.networkmanager.dns = "none";

  boot.supportedFilesystems = [ "ntfs" ];
}
