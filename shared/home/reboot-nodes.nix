# shared/home/reboot-nodes.nix
# Rolling, one-node-at-a-time reboot of the cluster with cordon/drain and
# Longhorn-aware waits. Interactive only: refuses without a TTY and demands
# the node list typed back, so neither an agent nor a stray script can fire
# it. Procedure and rationale: docs/reboot-resilience-research.md §5.
{ lib, pkgs, ... }:

let
  rebootNodes = pkgs.writeShellApplication {
    name = "reboot-nodes";
    runtimeInputs = [ pkgs.kubectl pkgs.openssh pkgs.jq pkgs.coreutils pkgs.gnugrep ];
    text = ''
      usage() {
        cat <<EOF
      usage: reboot-nodes [--force] [--no-scale] [node...]

      Reboots nodes one at a time, default order node2 node3 node1 (master
      last, so the API stays up for the workers). Per node: skip unless the
      booted kernel/initrd differs from the current generation (--force
      reboots anyway); scale to 0 every Deployment/StatefulSet whose Longhorn
      volume has all its replicas on that node (--no-scale skips this; the
      drain will then block on jellyfin-data); cordon; drain; sudo reboot over
      ssh; wait for ssh, node Ready, Longhorn Ready and volumes settled;
      uncordon; scale back; wait for the pods.

      Interactive only. You will type the node list back, then sudo's
      password once per node.
      EOF
      }

      FORCE=0
      SCALE=1
      NODES=()
      while [ $# -gt 0 ]; do
        case "$1" in
          --force) FORCE=1 ;;
          --no-scale) SCALE=0 ;;
          -h|--help) usage; exit 0 ;;
          -*) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
          *) NODES+=("$1") ;;
        esac
        shift
      done
      if [ "''${#NODES[@]}" -eq 0 ]; then NODES=(node2 node3 node1); fi

      if [ ! -t 0 ] || [ ! -t 1 ]; then
        echo "reboot-nodes: refusing to run without a terminal" >&2
        exit 3
      fi
      kubectl get nodes >/dev/null || { echo "reboot-nodes: cluster API unreachable" >&2; exit 1; }

      phrase="reboot ''${NODES[*]}"
      echo "This reboots, in order: ''${NODES[*]}"
      printf 'Type "%s" to continue: ' "$phrase"
      read -r typed
      [ "$typed" = "$phrase" ] || { echo "aborted" >&2; exit 3; }

      needs_reboot() {
        ssh "$1" 'for f in kernel initrd kernel-modules; do
          [ "$(readlink -f /run/booted-system/$f)" = "$(readlink -f /run/current-system/$f)" ] || exit 0
        done; exit 1'
      }

      # Deployments/StatefulSets whose pods mount a Longhorn volume with every
      # replica on this node. Longhorn's drain policy is
      # allow-if-replica-is-stopped, so these must be stopped, not merely
      # cordoned around.
      consumers_on() {
        local node="$1"
        local vols
        vols=$(kubectl -n longhorn-system get replicas.longhorn.io -o json \
          | jq -r --arg n "$node" '
              [.items[] | {v: .spec.volumeName, n: .spec.nodeID}]
              | group_by(.v) | map(select(all(.[]; .n == $n))) | map(.[0].v) | .[]')
        [ -n "$vols" ] || return 0
        kubectl get pv -o json \
          | jq -r --argjson vols "$(printf '%s\n' "$vols" | jq -R . | jq -s .)" '
              .items[] | select(.spec.csi.driver == "driver.longhorn.io")
              | select(.metadata.name as $n | $vols | index($n))
              | "\(.spec.claimRef.namespace)/\(.spec.claimRef.name)"' \
          | while IFS=/ read -r ns pvc; do
              kubectl -n "$ns" get pods -o json \
                | jq -r --arg pvc "$pvc" '
                    .items[] | select(.spec.volumes[]?.persistentVolumeClaim.claimName == $pvc)
                    | .metadata.ownerReferences[]? | select(.kind == "ReplicaSet" or .kind == "StatefulSet")
                    | "\(.kind)/\(.name)"' \
                | sort -u | while IFS=/ read -r kind name; do
                    if [ "$kind" = ReplicaSet ]; then
                      owner=$(kubectl -n "$ns" get rs "$name" -o jsonpath='{.metadata.ownerReferences[0].name}')
                      [ -n "$owner" ] && echo "$ns deployment $owner"
                    else
                      echo "$ns statefulset $name"
                    fi
                  done
            done | sort -u
      }

      wait_for() {  # wait_for <label> <seconds> <command...>
        local label="$1" secs="$2"; shift 2
        local i=0
        until "$@"; do
          i=$((i + 5))
          [ "$i" -ge "$secs" ] && { echo "reboot-nodes: timed out waiting for $label" >&2; return 1; }
          sleep 5
        done
      }
      node_ready()     { [ "$(kubectl get node "$1" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)" = True ]; }
      longhorn_ready() { [ "$(kubectl -n longhorn-system get nodes.longhorn.io "$1" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)" = True ]; }
      volumes_settled() { ! kubectl -n longhorn-system get volumes.longhorn.io -o jsonpath='{range .items[*]}{.status.state}/{.status.robustness}{"\n"}{end}' | grep -qE 'attaching|detaching|faulted'; }
      ssh_down() { ! ssh -o ConnectTimeout=3 -o BatchMode=yes "$1" true 2>/dev/null; }
      ssh_up()   { ssh -o ConnectTimeout=3 -o BatchMode=yes "$1" true 2>/dev/null; }

      for n in "''${NODES[@]}"; do
        echo "==> $n"
        if [ "$FORCE" = 0 ] && ! needs_reboot "$n"; then
          echo "    booted generation is current; skipping (--force to reboot anyway)"
          continue
        fi

        scaled=()
        if [ "$SCALE" = 1 ]; then
          while read -r ns kind name; do
            [ -n "$name" ] || continue
            replicas=$(kubectl -n "$ns" get "$kind/$name" -o jsonpath='{.spec.replicas}')
            echo "    scaling $ns/$kind/$name $replicas -> 0 (its volume lives only on $n)"
            kubectl -n "$ns" scale "$kind/$name" --replicas=0 >/dev/null
            scaled+=("$ns $kind $name $replicas")
          done < <(consumers_on "$n")
        fi

        echo "    cordon + drain"
        kubectl cordon "$n" >/dev/null
        kubectl drain "$n" --ignore-daemonsets --delete-emptydir-data --timeout=600s

        echo "    rebooting (sudo password for $n)"
        ssh -t "$n" 'sudo systemctl reboot' || true
        wait_for "$n to go down" 120 ssh_down "$n"
        wait_for "$n ssh" 900 ssh_up "$n"
        echo "    back: $(ssh "$n" uname -r)"
        wait_for "$n Ready" 600 node_ready "$n"
        wait_for "Longhorn on $n" 600 longhorn_ready "$n"
        kubectl uncordon "$n" >/dev/null

        for entry in "''${scaled[@]}"; do
          read -r ns kind name replicas <<<"$entry"
          echo "    scaling $ns/$kind/$name back to $replicas"
          kubectl -n "$ns" scale "$kind/$name" --replicas="$replicas" >/dev/null
        done
        wait_for "volumes to settle" 900 volumes_settled
        for entry in "''${scaled[@]}"; do
          read -r ns kind name _ <<<"$entry"
          kubectl -n "$ns" rollout status "$kind/$name" --timeout=600s || true
        done
        echo "    $n done"
      done
      echo "reboot-nodes: done"
    '';
  };
in
{
  home.packages = lib.optionals pkgs.stdenv.hostPlatform.isLinux [ rebootNodes ];
}
