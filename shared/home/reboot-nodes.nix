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
      reboots anyway); cordon; stop every Deployment, StatefulSet and Scooter
      Sandbox whose Longhorn volume has all its replicas on that node
      (--no-scale skips this; the drain will then block on jellyfin-data);
      wait for those volumes to detach, naming whatever still holds one;
      drain; sudo reboot over ssh; wait for ssh, node Ready, etcd active, Longhorn Ready;
      uncordon; restart the stopped workloads; wait for every volume to be
      healthy. A health line prints every 30s during each wait. On failure or
      ^C the stopped workloads are restarted and the node uncordoned.

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

      local_volumes() {  # Longhorn volumes whose every replica sits on <node>
        kubectl -n longhorn-system get replicas.longhorn.io -o json \
          | jq -r --arg n "$1" '
              [.items[] | {v: .spec.volumeName, n: .spec.nodeID}]
              | group_by(.v) | map(select(all(.[]; .n == $n))) | map(.[0].v) | .[]'
      }

      attached_local_volumes() {  # "<volume> <ns>/<pvc>" for local volumes not yet detached
        local vols
        vols=$(local_volumes "$1")
        [ -n "$vols" ] || return 0
        kubectl -n longhorn-system get volumes.longhorn.io -o json \
          | jq -r --argjson vols "$(printf '%s\n' "$vols" | jq -R . | jq -s .)" '
              .items[] | select(.metadata.name as $n | $vols | index($n))
              | select(.status.state != "detached")
              | select(.status.kubernetesStatus.pvcName != null)
              | "\(.metadata.name) \(.status.kubernetesStatus.namespace)/\(.status.kubernetesStatus.pvcName)"'
      }
      local_volumes_detached() { [ -z "$(attached_local_volumes "$1")" ]; }

      holders_of() {  # stdin "<ns>/<pvc>" -> "<ns> <pod> <ownerKind> <ownerName> <node>" for live pods
        while IFS=/ read -r ns pvc; do
          kubectl -n "$ns" get pods -o json \
            | jq -r --arg ns "$ns" --arg pvc "$pvc" '
                .items[] | select(.spec.volumes[]?.persistentVolumeClaim.claimName == $pvc)
                | select(.status.phase == "Running" or .status.phase == "Pending")
                | "\($ns) \(.metadata.name) \(.metadata.ownerReferences[0].kind // "Pod") \(.metadata.ownerReferences[0].name // .metadata.name) \(.spec.nodeName // "-")"'
        done | sort -u
      }

      consumers_on() {  # "<ns> <kind> <name>" workloads that must stop before <node> drains
        kubectl get pv -o json \
          | jq -r --argjson vols "$(local_volumes "$1" | jq -R . | jq -s .)" '
              .items[] | select(.spec.csi.driver == "driver.longhorn.io")
              | select(.metadata.name as $n | $vols | index($n))
              | "\(.spec.claimRef.namespace)/\(.spec.claimRef.name)"' \
          | holders_of | while read -r ns _ kind name _; do
              case "$kind" in
                ReplicaSet)
                  owner=$(kubectl -n "$ns" get rs "$name" -o jsonpath='{.metadata.ownerReferences[0].name}')
                  [ -n "$owner" ] && echo "$ns deployment $owner" ;;
                StatefulSet) echo "$ns statefulset $name" ;;
                Sandbox) echo "$ns sandbox $name" ;;
              esac
            done | sort -u
      }

      stop_workload() {  # stop_workload <ns> <kind> <name>; prints the setting to restore
        local ns="$1" kind="$2" name="$3" prev
        case "$kind" in
          sandbox)
            prev=$(kubectl -n "$ns" get sandbox "$name" -o jsonpath='{.spec.operatingMode}')
            kubectl -n "$ns" patch sandbox "$name" --type merge -p '{"spec":{"operatingMode":"Suspended"}}' >/dev/null ;;
          *)
            prev=$(kubectl -n "$ns" get "$kind/$name" -o jsonpath='{.spec.replicas}')
            kubectl -n "$ns" scale "$kind/$name" --replicas=0 >/dev/null ;;
        esac
        echo "$prev"
      }
      start_workload() {  # start_workload <ns> <kind> <name> <setting>
        local ns="$1" kind="$2" name="$3" prev="$4"
        case "$kind" in
          sandbox) kubectl -n "$ns" patch sandbox "$name" --type merge -p "{\"spec\":{\"operatingMode\":\"$prev\"}}" >/dev/null ;;
          *) kubectl -n "$ns" scale "$kind/$name" --replicas="$prev" >/dev/null ;;
        esac
      }

      health() {  # health <node>: one-line snapshot of the node and the cluster
        local n="$1" up node lh vols pods
        up=$(ssh -o ConnectTimeout=3 -o BatchMode=yes "$n" 'cut -d. -f1 /proc/uptime' 2>/dev/null || true)
        node=$(kubectl get node "$n" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
        lh=$(kubectl -n longhorn-system get nodes.longhorn.io "$n" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
        vols=$(kubectl -n longhorn-system get volumes.longhorn.io -o jsonpath='{range .items[*]}{.status.state}/{.status.robustness}{"\n"}{end}' 2>/dev/null \
               | sort | uniq -c | awk '{printf "%s%s=%s", sep, $2, $1; sep=" "}')
        pods=$(kubectl get pods -A --no-headers 2>/dev/null | grep -cvE 'Running|Completed' || true)
        local ssh="down"
        [ -n "$up" ] && ssh="up ''${up}s"
        echo "ssh $ssh | node Ready=''${node:-?} | longhorn Ready=''${lh:-?} | volumes ''${vols:-?} | pods not running: ''${pods:-?}"
      }

      wait_for() {  # wait_for <label> <seconds> <command...>
        local label="$1" secs="$2"; shift 2
        local i=0
        until "$@"; do
          i=$((i + 5))
          [ "$i" -ge "$secs" ] && { echo "reboot-nodes: timed out waiting for $label" >&2; return 1; }
          [ $((i % 30)) -eq 0 ] && echo "    [''${i}s] $label: $(health "$n")"
          sleep 5
        done
      }
      node_ready()     { [ "$(kubectl get node "$1" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)" = True ]; }
      longhorn_ready() { [ "$(kubectl -n longhorn-system get nodes.longhorn.io "$1" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)" = True ]; }
      volumes_settled() { ! kubectl -n longhorn-system get volumes.longhorn.io -o jsonpath='{range .items[*]}{.status.state}/{.status.robustness}{"\n"}{end}' | grep -qE 'attaching|detaching|faulted|degraded'; }
      etcd_active() { [ "$(ssh -o ConnectTimeout=3 -o BatchMode=yes "$1" systemctl is-active etcd 2>/dev/null)" = active ]; }
      ssh_down() { ! ssh -o ConnectTimeout=3 -o BatchMode=yes "$1" true 2>/dev/null; }
      ssh_up()   { ssh -o ConnectTimeout=3 -o BatchMode=yes "$1" true 2>/dev/null; }

      stopped=()
      n=""
      rebooted=0
      restore_stopped() {
        local entry ns kind name prev
        for entry in "''${stopped[@]}"; do
          read -r ns kind name prev <<<"$entry"
          echo "    restoring $ns/$kind/$name -> $prev"
          start_workload "$ns" "$kind" "$name" "$prev" || true
        done
        stopped=()
      }
      cleanup() {
        local rc=$?
        [ "$rc" -eq 0 ] && return
        trap - EXIT
        echo "reboot-nodes: failed on $n (exit $rc); restoring" >&2
        restore_stopped
        if [ -n "$n" ] && [ "$rebooted" = 0 ]; then
          echo "    uncordon $n" >&2
          kubectl uncordon "$n" >/dev/null || true
        fi
        exit "$rc"
      }
      trap cleanup EXIT
      trap 'exit 130' INT

      for n in "''${NODES[@]}"; do
        echo "==> $n"
        if [ "$FORCE" = 0 ] && ! needs_reboot "$n"; then
          echo "    booted generation is current; skipping (--force to reboot anyway)"
          continue
        fi
        rebooted=0

        echo "    cordon"
        kubectl cordon "$n" >/dev/null
        if [ "$SCALE" = 1 ]; then
          while read -r ns kind name; do
            [ -n "$name" ] || continue
            prev=$(stop_workload "$ns" "$kind" "$name")
            echo "    stopping $ns/$kind/$name (was $prev; its volume lives only on $n)"
            stopped+=("$ns $kind $name $prev")
          done < <(consumers_on "$n")
        fi
        if ! wait_for "volumes on $n to detach" 300 local_volumes_detached "$n"; then
          attached_local_volumes "$n" | while read -r vol claim; do
            echo "    still attached: $vol ($claim)" >&2
            echo "$claim" | holders_of | while read -r ns pod kind name node; do
              echo "      held by $ns/$pod ($kind/$name on $node)" >&2
            done
          done
          exit 1
        fi

        echo "    drain"
        kubectl drain "$n" --ignore-daemonsets --delete-emptydir-data --timeout=600s

        echo "    rebooting (sudo password for $n)"
        rebooted=1
        ssh -t "$n" 'sudo systemctl reboot' || true
        wait_for "$n to go down" 120 ssh_down "$n"
        wait_for "$n ssh" 900 ssh_up "$n"
        echo "    back: $(ssh "$n" uname -r)"
        wait_for "$n Ready" 600 node_ready "$n"
        wait_for "etcd on $n" 1200 etcd_active "$n"
        wait_for "Longhorn on $n" 600 longhorn_ready "$n"
        kubectl uncordon "$n" >/dev/null

        restarting=("''${stopped[@]}")
        restore_stopped
        wait_for "volumes to settle" 1800 volumes_settled
        for entry in "''${restarting[@]}"; do
          read -r ns kind name _ <<<"$entry"
          [ "$kind" = sandbox ] && continue
          kubectl -n "$ns" rollout status "$kind/$name" --timeout=600s || true
        done
        echo "    $n done"
      done
      n=""
      echo "reboot-nodes: done"
    '';
  };
in
{
  home.packages = lib.optionals pkgs.stdenv.hostPlatform.isLinux [ rebootNodes ];
}
