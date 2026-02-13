# server-common.nix
{ hostname, ip, ... }:
{
  networking.hostName = hostname;
  networking.interfaces.eno1.ipv4.addresses = [{
    address = ip;
    prefixLength = 24;
  }];
}
