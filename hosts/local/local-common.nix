# hosts/local/local-common.nix
# Override common.nix settings for local desktop use
{ config, lib, pkgs, ... }:

{
  # Disable server-oriented services
  services.fail2ban.enable = lib.mkForce false;
  services.tailscale.enable = lib.mkForce false;
  services.certmgr.enable = lib.mkForce false;
  
  # Disable NFS server support (keep client support from common.nix)
  services.rpcbind.enable = lib.mkForce false;
  boot.supportedFilesystems = lib.mkForce [ "ntfs" ];
  
  # Disable Longhorn mount fix
  system.activationScripts.longhornMountFix = lib.mkForce "";
  
  # More permissive firewall for desktop use
  networking.firewall = lib.mkForce {
    enable = false;  # More convenient for desktop
  };
  
  # SSH settings for desktop (allow password for convenience)
  services.openssh.settings = lib.mkForce {
    PasswordAuthentication = true;
    KbdInteractiveAuthentication = true;
    PermitRootLogin = "no";
    PubkeyAuthentication = true;
    X11Forwarding = true;
  };
}
