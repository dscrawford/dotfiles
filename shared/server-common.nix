# Configuration specific to server systems (not desktops)
{ config, lib, pkgs, hostname, ip, netInterface ? "eno1", isMaster, kubeMasterIP, kubeMasterHostname, ... }:

{
  # === Services ===
  services = {
    # Security services
    fail2ban = {
      enable = true;
      maxretry = 10;
      bantime = "15m";
      jails = {
        sshd.enabled = true;
      };
    };

    # Tailscale VPN
    tailscale = {
      enable = true;
      extraUpFlags = [ "--hostname=${hostname}" "--accept-dns=false" ];
    };

    # Certificate management
    certmgr.renewInterval = "24h";
  };

  # === Environment ===
  environment.systemPackages = with pkgs; [
    nfs-utils
    lm_sensors
  ];

  # === System Activation ===
  # Longhorn NFS mount path fix for Kubernetes
  system.activationScripts.longhornMountFix = ''
    mkdir -p /usr/bin
    ln -sf /run/wrappers/bin/mount /usr/bin/mount
    ln -sf /run/current-system/sw/bin/mount.nfs /usr/bin/mount.nfs
    ln -sf /run/wrappers/bin/umount /usr/bin/umount
  '';

  # === Networking ===
  networking = {
    hostName = hostname;
    useDHCP = false;
    
    # Static IP configuration
    interfaces.${netInterface} = {
      useDHCP = false;
      ipv4.addresses = [{
        address = ip;
        prefixLength = 24;
      }];
    };
    
    defaultGateway = "192.168.0.1";
    nameservers = [ "192.168.0.1" "1.1.1.1" ];
    
    # Kubernetes cluster hosts
    extraHosts = ''
      ${kubeMasterIP} ${kubeMasterHostname}
      192.168.0.2 node1
      192.168.0.4 node2
      192.168.0.6 node3
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
}
