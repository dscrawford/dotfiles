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
    for app in ${pkgs.emacs-30}/Applications/*.app; do
      cp -rL "$app" /Applications/Nix\ Apps/
    done
  '';

  # Export system PATH to launchd so GUI Emacs can find Nix binaries
  launchd.agents.set-environment-path = {
    serviceConfig = {
      Label = "set-environment-path";
      ProgramArguments = [
        "/bin/sh" "-c"
        "launchctl setenv PATH $PATH"
      ];
      RunAtLoad = true;
    };
  };

  # Shell setup — keep zsh enabled (macOS requires it) but add bash to allowed shells
  programs.zsh.enable = true;
  programs.bash.enable = true;
  environment.shells = [ pkgs.bash ];

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
