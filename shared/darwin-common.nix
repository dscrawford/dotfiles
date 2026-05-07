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

  system = {
    stateVersion = 5;
    primaryUser = username;
    # Symlink Emacs.app to /Applications/Nix Apps for Spotlight
    activationScripts.applications.text = pkgs.lib.mkForce ''
      echo "setting up /Applications/Nix Apps..." >&2
      rm -rf /Applications/Nix\ Apps
      mkdir -p /Applications/Nix\ Apps
      for app in ${pkgs.emacs30}/Applications/*.app; do
        cp -rL "$app" /Applications/Nix\ Apps/
      done
    '';
    # Ensure user is a trusted Nix user (macOS doesn't resolve group membership correctly)
    # See: https://github.com/NixOS/nix/issues/5885
    # See: https://gerrit.lix.systems/c/lix/+/2566 (proper daemon fix, not yet shipped)
    # Determinate Nix overwrites /etc/nix/nix.conf — use nix.custom.conf instead
    activationScripts.postActivation.text = ''
      if ! grep -q "trusted-users.*${username}" /etc/nix/nix.custom.conf 2>/dev/null; then
        echo "trusted-users = root ${username}" >> /etc/nix/nix.custom.conf
        echo "Restarting nix-daemon to apply trusted-users..."
        launchctl kickstart -k system/org.nixos.nix-daemon 2>/dev/null || true
      fi
    '';
  };

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

  security.pam.services.sudo_local.touchIdAuth = true;

  # Disable nix-daemon management (using Determinate Nix)
  nix.enable = false;

  # Allow unfree packages (e.g., claude-code)
  nixpkgs.config.allowUnfree = true;
}
