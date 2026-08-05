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
    # macOS doesn't resolve group membership for trusted users (NixOS/nix#5885),
    # so name the user explicitly. Determinate Nix overwrites /etc/nix/nix.conf,
    # hence nix.custom.conf.
    # Note: /Applications/Nix Apps/Emacs.app is hand-made, not managed here.
    activationScripts.postActivation.text = ''
      if ! grep -q "trusted-users.*${username}" /etc/nix/nix.custom.conf 2>/dev/null; then
        echo "trusted-users = root ${username}" >> /etc/nix/nix.custom.conf
        echo "Restarting nix-daemon to apply trusted-users..."
        launchctl kickstart -k system/org.nixos.nix-daemon 2>/dev/null || true
      fi
    '';
  };

  # So GUI Emacs can find Nix binaries.
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

  # zsh stays enabled because macOS requires it; bash is the actual shell.
  programs.zsh.enable = true;
  programs.bash.enable = true;
  environment.shells = [ pkgs.bash ];

  security.pam.services.sudo_local.touchIdAuth = true;

  # Determinate Nix manages the daemon.
  nix.enable = false;

  nixpkgs.config.allowUnfree = true;
}
