# shared/nix-gc.nix
# Store-retention policy, system half.
#
# A single GC pass cannot prune every profile: nix-collect-garbage only walks
# the profile directories belonging to the user that runs it. Root's
# nix-gc.service therefore covers /nix/var/nix/profiles (system generations),
# and shared/home/nix-gc.nix covers ~/.local/state/nix/profiles
# (home-manager generations), which root never sees.
{ ... }:
{
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 7d";
  };

  # Hard-link identical files across store paths. The generations kept here
  # overlap almost completely, so dedup is worth far more than the retention
  # window: it was already reclaiming ~90 GiB when this was manual-only.
  nix.optimise = {
    automatic = true;
    dates = [ "weekly" ];
  };
}
