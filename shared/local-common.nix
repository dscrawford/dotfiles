# local-common.nix
# Desktop-specific configuration overrides
{ lib, ... }:

{
  services.openssh.settings = {
    PasswordAuthentication = lib.mkForce true;
    KbdInteractiveAuthentication = lib.mkForce true;
    X11Forwarding = lib.mkForce true;
  };

  networking.firewall.enable = lib.mkForce false;

  # The tailnet is how game bytes reach this machine from the cluster: the
  # library's NodePort is only ever addressed by a node's tailscale IP, so a
  # download rides WireGuard end to end instead of the ProtonVPN hairpin.
  # Join once with `sudo tailscale up`; the state survives rebuilds.
  services.tailscale.enable = true;

  # Router (192.168.0.1) DHCP hands out its own DNS, whose forwarder is
  # unreliable — bypass it with public resolvers.
  networking.nameservers = [ "1.1.1.1" "9.9.9.9" ];
  networking.networkmanager.dns = "none";

  boot.supportedFilesystems = [ "ntfs" ];
}
