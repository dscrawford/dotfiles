# Recover Longhorn RWX consumers left with stale NFS mounts after an outage.
#
# A share-manager pod recreated after a consumer mounted its export invalidates
# the consumer's file handles; the pod stays Running (its probes don't touch the
# mount) but every read fails ESTALE. Only recreating the pod fixes it.
# Repaired out-of-band rather than via livenessProbe, so Jellyfin keeps its
# documented "a heavy transcode must never trigger a restart" guarantee.
# Master-only, so one sweep per cluster. Full runbook: Kubernetes repo,
# docs/power-outage-recovery.md and scripts/check-stale-nfs-mounts.sh.
{ config, pkgs, lib, ... }:

let
  isMaster = config.services.kubernetes.apiserver.enable;

  kubeconfig = "/etc/kubernetes/cluster-admin.kubeconfig";

  apiTimeoutSec = 600;
  # Share managers must be Running and unchanged this long before we judge any
  # consumer stale, so we don't act mid-churn.
  settleSec = 90;
  settleTimeoutSec = 900;

  recoverScript = pkgs.writeShellApplication {
    name = "kube-stale-mount-recovery";
    runtimeInputs = [ pkgs.kubectl pkgs.python3 pkgs.coreutils pkgs.gnugrep ];
    text = ''
      # An inherited KUBECONFIG wins, so this stays runnable by hand.
      export KUBECONFIG="''${KUBECONFIG:-${kubeconfig}}"
      log() { echo "kube-stale-mount-recovery: $*"; }

      if [ ! -e "$KUBECONFIG" ]; then
        log "no kubeconfig at $KUBECONFIG, skipping"
        exit 0
      fi

      # --- Wait for the API server ------------------------------------------
      deadline=$(( $(date +%s) + ${toString apiTimeoutSec} ))
      until kubectl --request-timeout=10s get --raw /readyz >/dev/null 2>&1; do
        if [ "$(date +%s)" -ge "$deadline" ]; then
          log "API server not ready after ${toString apiTimeoutSec}s, giving up"
          exit 0
        fi
        sleep 10
      done
      log "API server ready"

      # --- Wait for share managers to settle --------------------------------
      # Acting mid-recreation would restart consumers about to go stale again.
      deadline=$(( $(date +%s) + ${toString settleTimeoutSec} ))
      while :; do
        not_running=$(kubectl -n longhorn-system get pods \
          -l longhorn.io/component=share-manager \
          --no-headers 2>/dev/null | grep -cv ' Running ' || true)
        youngest=$(kubectl -n longhorn-system get pods \
          -l longhorn.io/component=share-manager \
          -o jsonpath='{range .items[*]}{.status.startTime}{"\n"}{end}' 2>/dev/null \
          | sort | tail -1)

        age=999999
        if [ -n "$youngest" ]; then
          started=$(date -d "$youngest" +%s 2>/dev/null || echo 0)
          [ "$started" -gt 0 ] && age=$(( $(date +%s) - started ))
        fi

        if [ "''${not_running:-0}" -eq 0 ] && [ "$age" -ge ${toString settleSec} ]; then
          break
        fi
        if [ "$(date +%s)" -ge "$deadline" ]; then
          log "share managers still unsettled after ${toString settleTimeoutSec}s, sweeping anyway"
          break
        fi
        sleep 15
      done

      # --- Build the consumer list ------------------------------------------
      # volume -> PV (claimRef) -> PVC -> pod -> container -> mountPath.
      plan=$(python3 - <<'PYEOF'
import json, subprocess, sys

def kget(*args):
    r = subprocess.run(["kubectl", *args, "-o", "json"],
                       capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit(0)
    return json.loads(r.stdout)

sms = kget("-n", "longhorn-system", "get", "sharemanagers.longhorn.io")
rwx = {i["metadata"]["name"] for i in sms.get("items", [])}
if not rwx:
    sys.exit(0)

claims = {}
for pv in kget("get", "pv").get("items", []):
    name = pv["metadata"]["name"]
    if name in rwx:
        ref = pv["spec"].get("claimRef") or {}
        if ref.get("namespace") and ref.get("name"):
            claims[name] = (ref["namespace"], ref["name"])

for pod in kget("get", "pods", "-A").get("items", []):
    meta, spec = pod["metadata"], pod["spec"]
    if pod.get("status", {}).get("phase") != "Running":
        continue
    ns = meta["namespace"]
    local = {}
    for v in spec.get("volumes", []):
        pvc = (v.get("persistentVolumeClaim") or {}).get("claimName")
        if not pvc:
            continue
        for vol, (cns, cname) in claims.items():
            if cns == ns and cname == pvc:
                local[v["name"]] = vol
    if not local:
        continue
    for c in spec.get("containers", []):
        for m in c.get("volumeMounts", []):
            # subPath mounts resolve inside the export; skipped to avoid false
            # positives on a path that legitimately may not exist.
            if m["name"] in local and not m.get("subPath"):
                print("\t".join([ns, meta["name"], c["name"], m["mountPath"]]))
PYEOF
      ) || true

      if [ -z "$plan" ]; then
        log "no Running pods mount an RWX volume, nothing to do"
        exit 0
      fi

      # --- Probe each mount --------------------------------------------------
      owners=""
      stale=0
      checked=0

      while IFS="$(printf '\t')" read -r ns pod container path; do
        [ -n "$ns" ] || continue
        checked=$(( checked + 1 ))

        out=$(kubectl -n "$ns" exec "$pod" -c "$container" --request-timeout=20s \
                -- ls "$path" 2>&1 >/dev/null) || true

        if [ -z "$out" ]; then
          continue
        fi

        if printf '%s' "$out" | grep -qi 'stale file handle'; then
          log "STALE $ns/$pod [$container] $path"
          stale=$(( stale + 1 ))
          rs=$(kubectl -n "$ns" get pod "$pod" \
                 -o jsonpath='{.metadata.ownerReferences[0].name}' 2>/dev/null || true)
          # ownerReferences names the ReplicaSet; strip the suffix for the Deployment.
          if [ -n "$rs" ]; then
            owners="$owners$ns ''${rs%-*}
"
          fi
        else
          # Minimal image, no shell. Report only — the timestamp heuristic that
          # would guess here isn't safe unattended; use the repo script by hand.
          log "UNPROBEABLE $ns/$pod [$container] $path"
        fi
      done <<EOF
$plan
EOF

      if [ "$stale" -eq 0 ]; then
        log "checked $checked mount(s), none stale"
        exit 0
      fi

      # --- Restart the owning deployments -----------------------------------
      printf '%s' "$owners" | sort -u | while read -r ns dep; do
        [ -n "$dep" ] || continue
        if ! kubectl -n "$ns" get deployment "$dep" >/dev/null 2>&1; then
          log "SKIP $ns/$dep is not a Deployment, restart its owner manually"
          continue
        fi
        log "restarting deployment/$dep in $ns"
        if kubectl -n "$ns" rollout restart "deployment/$dep"; then
          kubectl -n "$ns" rollout status "deployment/$dep" --timeout=300s || \
            log "WARNING: $ns/$dep did not become ready in time"
        else
          log "WARNING: could not restart $ns/$dep"
        fi
      done

      log "done, repaired $stale stale mount(s)"
    '';
  };
in
{
  # World-readable store path, but the certs it points at stay root-only.
  services.kubernetes.pki.etcClusterAdminKubeconfig =
    lib.mkIf isMaster "kubernetes/cluster-admin.kubeconfig";

  systemd.services.kube-stale-mount-recovery = lib.mkIf isMaster {
    description = "Repair stale Longhorn RWX NFS mounts after an outage";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${recoverScript}/bin/kube-stale-mount-recovery";
    };
    after = [ "network-online.target" "kube-apiserver.service" ];
    wants = [ "network-online.target" ];
  };

  systemd.timers.kube-stale-mount-recovery = lib.mkIf isMaster {
    description = "Periodic stale Longhorn RWX mount check";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      # Keeps checking after boot: a share manager can be rescheduled any time.
      OnBootSec = "3min";
      OnUnitActiveSec = "15min";
    };
  };
}
