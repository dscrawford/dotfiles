# Configuration specific to server systems (not desktops)
{ config, lib, pkgs, hostname, ip, netInterface ? "eno1", isMaster, kubeMasterIP, kubeMasterHostname, ... }:

{
  services = {
    fail2ban = {
      enable = true;
      maxretry = 10;
      bantime = "15m";
      jails = {
        sshd.enabled = true;
      };
    };

    tailscale = {
      enable = true;
      extraUpFlags = [ "--hostname=${hostname}" "--accept-dns=false" ];
    };

    certmgr.renewInterval = "24h";
  };

  environment.systemPackages = with pkgs; [
    nfs-utils
    lm_sensors
  ];

  # Longhorn expects mount helpers at FHS paths.
  system.activationScripts.longhornMountFix = ''
    mkdir -p /usr/bin
    ln -sf /run/wrappers/bin/mount /usr/bin/mount
    ln -sf /run/current-system/sw/bin/mount.nfs /usr/bin/mount.nfs
    ln -sf /run/wrappers/bin/umount /usr/bin/umount
  '';

  networking = {
    hostName = hostname;
    useDHCP = false;
    
    interfaces.${netInterface} = {
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
      192.168.0.4 node2
      192.168.0.6 node3
    '';

    firewall = {
      allowedTCPPorts = [ 22 8080 6443 10250 8888 ];
      allowedTCPPortRanges = [
        { from = 30500; to = 30799; }
      ];
      allowedUDPPorts = [ 51820 ];
      allowedUDPPortRanges = [
        { from = 30800; to = 30899; }
      ];
    };
  };
}
