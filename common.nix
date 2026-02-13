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

  services.tailscale.enable = {
    enable = true;
    extraUpFlags = [ "--hostname=${hostname}" ];
  };
  services.certmgr.renewInterval = "24h";

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  system.stateVersion = "25.11";
}
