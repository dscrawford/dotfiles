# server-common.nix
{ hostname, ip, ... }:
{
  networking.hostName = hostname;
  networking.useDHCP = false;
  networking.interfaces.eno1 = {
    useDHCP = false;
    ipv4.addresses = [{
      address = ip;
      prefixLength = 24;
    }];
  };
  networking.defaultGateway = "192.168.0.1";
  networking.nameservers = [ "192.168.0.1" "1.1.1.1" ];
}
