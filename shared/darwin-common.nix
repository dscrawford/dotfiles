# shared/darwin-common.nix
# Shared configuration for Darwin (macOS) systems
{ pkgs, hostname, username, ... }:

{
  networking.hostName = hostname;

  users.users.${username} = {
    name = username;
    home = "/Users/${username}";
  };

  environment.systemPackages = with pkgs; [
    vim
    wget
    coreutils
    openssl
    less
  ];

  # Symlink Emacs.app to /Applications/Nix Apps for Spotlight
  system.activationScripts.applications.text = pkgs.lib.mkForce ''
    echo "setting up /Applications/Nix Apps..." >&2
    rm -rf /Applications/Nix\ Apps
    mkdir -p /Applications/Nix\ Apps
    for app in ${pkgs.emacs-macport}/Applications/*.app; do
      cp -rL "$app" /Applications/Nix\ Apps/
    done
  '';

  programs.zsh.enable = true;

  system = {
    stateVersion = 5;
    primaryUser = username;
  };

  security.pam.services.sudo_local.touchIdAuth = true;

  # Disable nix-daemon management (using Determinate Nix)
  nix.enable = false;

  # Allow unfree packages (e.g., claude-code)
  nixpkgs.config.allowUnfree = true;
}
