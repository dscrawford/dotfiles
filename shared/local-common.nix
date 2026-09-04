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

  # The tailnet reaches the cluster's game NodePort over WireGuard instead of
  # the ProtonVPN hairpin. Desktop joins via a sops auth key (tailscale.nix);
  # terminal builds via `sudo tailscale up` once; state survives rebuilds.
  services.tailscale.enable = true;

  # Router (192.168.0.1) DHCP hands out its own DNS, whose forwarder is
  # unreliable — bypass it with public resolvers.
  networking.nameservers = [ "1.1.1.1" "9.9.9.9" ];
  networking.networkmanager.dns = "none";

  boot.supportedFilesystems = [ "ntfs" ];
}
