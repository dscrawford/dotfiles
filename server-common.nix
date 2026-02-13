# server-common.nix
{ hostname, ip, ... }:
{
  networking.hostName = hostname;
  networking.interfaces.en01.ipv4.addresses = [{
    address = ip;
    prefixLength = 24;
  }];
}
