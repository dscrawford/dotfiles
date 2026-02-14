# common.nix
{ config, lib, pkgs, hostname, ... }:
{
  networking.hostName = hostname;
  networking.networkmanager.enable = true;

  services.xserver.xkb.layout = "us";

  environment.systemPackages = with pkgs; [
    vim
    wget
    emacs-nox
    openssl
    less
    coreutils
    nfs-utils
  ];

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
      PubkeyAuthentication = true;
      X11Forwarding = false;
    };
  };

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 8080 6443 10250 8888 ];
    allowedTCPPortRanges = [
      { from = 30500; to = 30799; }
    ];
    allowedUDPPortRanges = [
      { from = 30800; to = 30899; }
    ];
    allowPing = false;
  };

  services.fail2ban = {
    enable = true;
    maxretry = 10;
    bantime = "15m";
    jails = {
      sshd.enabled = true;
    };
  };

  services.tailscale = {
    enable = true;
    extraUpFlags = [ "--hostname=${hostname}" "--accept-dns=false" ];
  };
  services.certmgr.renewInterval = "24h";

  # NFS Support
  boot.supportedFilesystems = [ "nfs" ];
  services.rpcbind.enable = true;

  # Longhorn NFS mount path fix
  system.activationScripts.longhornMountFix = ''
  mkdir -p /usr/bin
  ln -sf /run/wrappers/bin/mount /usr/bin/mount
  ln -sf /run/current-system/sw/bin/mount.nfs /usr/bin/mount.nfs
  ln -sf /run/wrappers/bin/umount /usr/bin/umount
  '';

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  system.stateVersion = "25.11";
}
