# common.nix
# Shared configuration for all systems (servers and desktops)
{ pkgs, hostname, ... }:
{
  networking.hostName = hostname;
  networking.networkmanager.enable = true;

  environment.systemPackages = with pkgs; [
    vim
    wget
    emacs-nox
    openssl
  ];

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  networking.firewall.allowPing = false;

  boot.kernelModules = [ "coretemp" ];

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    keep-outputs = true;
    keep-derivations = true;
  };

  system.stateVersion = "25.11";
}
