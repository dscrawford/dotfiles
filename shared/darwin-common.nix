# shared/darwin-common.nix
# Shared configuration for Darwin (macOS) systems
{ pkgs, hostname, ... }:

{
  networking.hostName = hostname;

  environment.systemPackages = with pkgs; [
    vim
    wget
    coreutils
    openssl
    less
  ];

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  services.nix-daemon.enable = true;
}
