# shared/home/nix-gc.nix
# Store-retention policy, user half. Linux only.
#
# Root's nix-gc.service (shared/nix-gc.nix) prunes /nix/var/nix/profiles but
# not ~/.local/state/nix/profiles, so home-manager generations accumulate
# indefinitely. Stale .direnv trees are the other half of the leak: each one
# is an indirect GC root pinning a whole flake-input closure long after the
# project was last touched.
{ lib, pkgs, username, ... }:

let
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
  isLinux = pkgs.stdenv.hostPlatform.isLinux;
  homeDir = if isDarwin then "/Users/${username}" else "/home/${username}";

  # Retention window for profile generations, matching the system policy.
  keepDays = 7;
  # .direnv trees untouched for this long are dropped; direnv rebuilds them
  # on the next cd into the project.
  direnvStaleDays = 30;
  # Scanning all of $HOME would walk Steam, Games and the model caches, so
  # search only the trees that actually hold flakes.
  direnvSearchRoots = [
    "${homeDir}/Documents"
    "${homeDir}/.local/dotfiles"
    "${homeDir}/.local/flakes"
  ];
in
{
  systemd.user.services.nix-gc = lib.mkIf isLinux {
    Unit.Description = "Prune home-manager generations and stale direnv roots";
    Service = {
      Type = "oneshot";
      ExecStart = let
        script = pkgs.writeShellApplication {
          name = "user-nix-gc";
          runtimeInputs = [ pkgs.nix pkgs.findutils pkgs.coreutils ];
          text = ''
            for root in ${lib.escapeShellArgs direnvSearchRoots}; do
              [ -d "$root" ] || continue
              find "$root" -type d -name .direnv -mtime +${toString direnvStaleDays} \
                -prune -print -exec rm -rf {} +
            done

            # Prunes ~/.local/state/nix/profiles, then collects whatever the
            # dropped generations and direnv roots were the last reference to.
            nix-collect-garbage --delete-older-than ${toString keepDays}d
          '';
        };
      in "${script}/bin/user-nix-gc";
    };
  };

  systemd.user.timers.nix-gc = lib.mkIf isLinux {
    Unit.Description = "Weekly home-manager generation and direnv root cleanup";
    Timer = {
      OnCalendar = "weekly";
      RandomizedDelaySec = "1h";
      Persistent = true;
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
