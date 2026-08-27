# common.nix
# Shared configuration for all systems (servers and desktops)
{ pkgs, hostname, ... }:
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
    allowedTCPPorts = [ 22 ];
    allowPing = false;
  };

  boot.kernelModules = [ "coretemp" ];

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    keep-outputs = true;
    keep-derivations = true;
  };

  system.stateVersion = "25.11";
}
