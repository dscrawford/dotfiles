# server-common.nix
# Configuration specific to server systems (not desktops)
{ config, lib, pkgs, hostname, ip, isMaster, kubeMasterIP, kubeMasterHostname, ... }:
{
  # Static IP networking configuration
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
      192.168.0.4 node2
    '';

    # Kubernetes firewall rules
    firewall = {
      allowedTCPPorts = [ 22 8080 6443 10250 8888 ];
      allowedTCPPortRanges = [
        { from = 30500; to = 30799; }
      ];
      allowedUDPPortRanges = [
        { from = 30800; to = 30899; }
      ];
    };
  };

  # Server-specific packages
  environment.systemPackages = with pkgs; [
    nfs-utils
    lm_sensors
  ];

  # Security services
  services.fail2ban = {
    enable = true;
    maxretry = 10;
    bantime = "15m";
    jails = {
      sshd.enabled = true;
    };
  };

  # Tailscale VPN
  services.tailscale = {
    enable = true;
    extraUpFlags = [ "--hostname=${hostname}" "--accept-dns=false" ];
  };

  # Certificate management
  services.certmgr.renewInterval = "24h";

  # NFS Support for Kubernetes storage
  boot.supportedFilesystems = [ "nfs" ];
  services.rpcbind.enable = true;

  # Longhorn NFS mount path fix for Kubernetes
  system.activationScripts.longhornMountFix = ''
    mkdir -p /usr/bin
    ln -sf /run/wrappers/bin/mount /usr/bin/mount
    ln -sf /run/current-system/sw/bin/mount.nfs /usr/bin/mount.nfs
    ln -sf /run/wrappers/bin/umount /usr/bin/umount
  '';
}
