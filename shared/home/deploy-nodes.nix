# shared/home/deploy-nodes.nix
# One-command fleet update: builds every node's closure here as a check, then
# has each node build and switch over ssh one at a time, workers before the
# master, waiting for each to report Ready before touching the next. Linux
# desktop only.
{ lib, pkgs, ... }:

let
  isLinux = pkgs.stdenv.hostPlatform.isLinux;

  deployNodes = pkgs.writeShellApplication {
    name = "deploy-nodes";
    runtimeInputs = [ pkgs.nixos-rebuild-ng pkgs.kubectl pkgs.openssh pkgs.git pkgs.coreutils ];
    text = ''
      usage() {
        cat <<EOF
      usage: deploy-nodes [--build-only] [--flake DIR] [node...]

      Default order: node2 node3 node1 — workers first so a bad config shows
      up on a kubelet before it reaches the apiserver. Builds run here first
      as a fleet-wide check, then each node rebuilds its own closure (the
      desktop cannot push unsigned outputs) and prompts for the remote sudo
      password. Nothing reboots; a kernel change is reported per node and
      left to you, one node at a time.
      EOF
      }

      FLAKE="''${DOTFILES:-$HOME/.local/dotfiles}"
      BUILD_ONLY=0
      NODES=()
      while [ $# -gt 0 ]; do
        case "$1" in
          --build-only) BUILD_ONLY=1 ;;
          --flake) FLAKE="$2"; shift ;;
          -h|--help) usage; exit 0 ;;
          -*) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
          *) NODES+=("$1") ;;
        esac
        shift
      done
      if [ "''${#NODES[@]}" -eq 0 ]; then NODES=(node2 node3 node1); fi

      # Flakes only see tracked files; a dirty tree deploys something other
      # than what git shows.
      if [ -n "$(git -C "$FLAKE" status --porcelain)" ]; then
        echo "deploy-nodes: $FLAKE has uncommitted changes; commit or stash first" >&2
        exit 1
      fi

      # Build everything before switching anything: an eval error on the last
      # node must not leave the fleet half-updated.
      for n in "''${NODES[@]}"; do
        echo "==> building $n"
        nixos-rebuild build --flake "$FLAKE#$n" --no-reexec
      done
      if [ "$BUILD_ONLY" = 1 ]; then echo "build-only: done"; exit 0; fi

      for n in "''${NODES[@]}"; do
        echo "==> switching $n"
        # The node builds its own closure: the desktop's outputs are unsigned
        # and `host` is not a nix trusted-user, so pushing them is refused.
        # Only content-addressed paths (derivations, fetched sources) cross
        # the wire, and the node substitutes the rest from cache.nixos.org.
        nixos-rebuild switch --flake "$FLAKE#$n" --target-host "$n" --build-host "$n" \
          --ask-elevate-password --no-reexec

        echo "    waiting for $n Ready"
        kubectl wait --for=condition=Ready "node/$n" --timeout=300s

        # switch does not reboot; a new kernel only takes effect after one.
        if ssh "$n" 'test "$(readlink /run/booted-system/kernel)" != "$(readlink /run/current-system/kernel)"'; then
          echo "    NOTE: $n has a new kernel staged; reboot it when convenient"
        fi
      done
      echo "deploy-nodes: done"
    '';
  };
in
{
  home.packages = lib.optionals isLinux [ deployNodes ];
}
