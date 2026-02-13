# server-common.nix
{ hostname, ip, isMaster, kubeMasterIP, kubeMasterHostname, ... }:
{
  networking = {
    hostName = hostname;
    useDHCP = false;
    
    interfaces.eno1 = {
      useDHCP = false;
      ipv4.addresses = [{
        address = ip;
        prefixLength = 24;
      }];
    };
    
    defaultGateway = "192.168.0.1";
    nameservers = [ "192.168.0.1" "1.1.1.1" ];
    
    extraHosts = ''
      ${kubeMasterIP} ${kubeMasterHostname}
      192.168.0.2 node1
      192.168.0.3 node2
    '';
  };
}
