# Kubernetes HA Migration Plan

## Problem

The cluster has a single master (node1). If node1 dies: no API server, no etcd, no scheduler — the entire control plane is gone. Workers keep running existing pods but nothing new can be scheduled, scaled, or managed.

## Current State

| Node | IP | Role | Storage | Special |
|------|-----|------|---------|---------|
| node1 | 192.168.0.2 | Master + Worker | SSD at /mnt/ssd | etcd, API server, controller-mgr, scheduler |
| node2 | 192.168.0.4 | Worker only | HDD at /mnt/hdd | |
| node3 | 192.168.0.6 | Worker only | RAID6 40TB at /mnt/storage | NVIDIA GPU |

**Single points of failure:**
1. etcd runs ONLY on node1 (single instance)
2. API server runs ONLY on node1
3. Controller-manager and scheduler run ONLY on node1
4. `kubeMasterIP = "192.168.0.2"` hardcoded in flake.nix — all workers point at node1
5. easyCerts PKI (CFSSL CA server) runs ONLY on node1

## Target Architecture

| Component | Current | Target |
|-----------|---------|--------|
| etcd | 1 node (node1) | 3-node cluster (quorum=2, survives 1 failure) |
| API server | node1 only | All 3 nodes behind floating VIP |
| Controller-mgr | node1 only | All 3 nodes (leader-elected) |
| Scheduler | node1 only | All 3 nodes (leader-elected) |
| API endpoint | `192.168.0.2` (node1) | `192.168.0.10` (floating VIP via keepalived) |
| CFSSL (CA) | node1 | node1 only, forced off elsewhere (renewal-only SPOF; certs valid 1 year) |
| SA signing key | per-node certmgr cert | one key from sops on all masters |
| Longhorn replicas | 3 default, 2 in default/retain classes | 3 for default/retain classes |

## Review 2026-10-30

Checked against nixpkgs `31ecbac` (`nixos/modules/services/cluster/kubernetes/`),
the live cluster (k8s 1.37.1, etcd 3.7.3, certs issued 2026-05-16 for one year,
CA valid to 2031), and every public NixOS HA cluster found (justinas,
misumisumi, starcraft66 — none use easyCerts; the manual still says
"Multi-master (HA) clusters are not supported by the easyCerts module").
The first draft below would not have produced a working cluster. What it missed:

| # | Blocker | Why | Fix |
|---|---------|-----|-----|
| 1 | **Service-account signing key differs per master** | `certs.serviceAccount` is a certmgr spec; each node mints its own key (`default.nix:298`, wired with `mkDefault` at `pki.nix:394,404`). Tokens signed by one apiserver are rejected by the other two. | One `sa.key` in `secrets/`, delivered by sops-nix (owner `kubernetes`), set on all three `serviceAccount*KeyFile` options. |
| 2 | **Three CAs and three API tokens** | `roles` containing `master` enables cfssl on every node (`pki.nix:146`); its preStart generates a CA and `apitoken.secret` when missing (`:180-198`). "CFSSL stays on node1" is not what the config would do. | `services.cfssl.enable = mkForce false` on node2/3, or ship `ca.pem`/`ca-key.pem`/`apitoken.secret` via sops with `genCfsslCACert = false; genCfsslAPIToken = false`. |
| 3 | **`masterAddress` cannot be the VIP while cfssl lives on node1** | certmgr's `remote` is `https://${masterAddress}:8888` (`pki.nix:48`). A VIP that floats to node2 breaks every renewal. | `masterAddress = "node1"` (cfssl host); `apiserverAddress = "https://api.kube:6443"` (VIP) set explicitly; VIP and all node IPs in `apiserver.extraSANs`. |
| 4 | **`pki.certs.etcd.hosts = mkForce …` destroys the cert spec** | `pki.certs` is `types.attrs`: shallow `//` merge, so overriding `hosts` drops `name`/`cert`/`key`/`action`. | Don't touch `pki.certs`. `apiserver.advertiseAddress = ip` already adds the node IP to the etcd and apiserver SANs (`apiserver.nix:544`); peer URLs must use exactly that IP. |
| 5 | **etcd overrides conflict** | `pki.nix:358-363` assigns the five etcd URL lists at normal priority; the current `systemd.services.etcd.environment` `mkForce` would clash with `services.etcd.*` for the same variables. | Use `services.etcd.*` with `mkForce` only; drop the environment override. `services.etcd.name` defaults to `masterAddress` on every node — set it per node. |
| 6 | **`advertiseAddress` breaks the default `apiserverAddress`** | `default.nix:345`: with `advertiseAddress` set the default URL has no port and points at the node, not the VIP. | Set `apiserverAddress` explicitly (already in the draft; keep it). |
| 7 | **keepalived health script silently ignored** | `vrrpScripts.*.user` defaults to `keepalived_script`, which the module never creates. VRRP is IP protocol 112, not a port. | `user = "root"` + `enableScriptSecurity`; `services.keepalived.openFirewall = true` (handles iptables and nftables on this nixpkgs). |
| 8 | **1→3 etcd without learners** | `member add` of a voter to a 1-member cluster stalls the cluster until the new member starts. | `member add --learner`, start, `member promote`; one node at a time. |
| 9 | **`kube-cert-renew.nix` token sync** | `isMaster = apiserver.enable` becomes true everywhere, so node2/3 stop syncing the token from node1. | Deliver `apitoken.secret` via sops; delete the ssh sync. |
| 10 | **Desktop and manifests pin node1's IP** | `hosts/local/local.nix:89` maps `api.kube` to `192.168.0.2`; five KubeServer manifests reference `192.168.0.2`. | Point at the VIP in the same change. |

Already done since the draft: Longhorn `default-replica-count` is 3 and the
`longhorn` class uses 3 replicas; `longhorn-default`/`longhorn-retain` still say 2.

Verdict: **feasible with easyCerts kept**, provided cfssl runs on node1 only and
the SA key, CA and API token come from sops. That makes every node able to hold
the control plane (etcd member, apiserver, leader-elected controller-manager and
scheduler, VIP). cfssl stays a renewal-only SPOF: with one-year certs, node1
being down costs nothing until a renewal falls due. The cleaner end state — a
hand-rolled PKI in `secrets/` with `easyCerts = false`, which is what every
real NixOS HA cluster does — drops cfssl, certmgr and `kube-cert-renew.nix`
entirely and is listed under Future Improvements.

## Key Design Decisions

### VIP: keepalived (VRRP)
Lightweight, no Kubernetes dependency, no chicken-and-egg problem (unlike kube-vip which runs inside K8s). The VIP `192.168.0.10` floats to whichever healthy node has highest priority. Health check curls the local API server — if unhealthy, priority drops and VIP moves. Unicast peers, `nopreempt`, `openFirewall` for protocol 112.

### All 3 nodes become master+worker
Controller-manager and scheduler already support leader election (`leaderElect = true` is the default in the NixOS module). Only one instance leads at a time; the others are standby. addon-manager runs on all three with no election; its `kubectl apply` is idempotent.

### easyCerts kept, cfssl on node1 only
Upstream `pki.nix` does not support multi-master ("easyCerts doesn't support multimaster clusters anyway atm", line 357). We keep `easyCerts = true` for certmgr renewal, force cfssl off on node2/3, and `mkForce` the etcd URL lists. `masterAddress` stays `node1` (it is the cfssl endpoint and the etcd cert CN); only `apiserverAddress` moves to the VIP.

### Shared secrets via sops-nix
`secrets/secrets.yaml` gains `k8s/sa.key` (RSA 4096, generated once), `k8s/apitoken.secret` (copied from node1's `/var/lib/cfssl/`) and `k8s/ca.pem` is already public. All three nodes decrypt with their host keys (already configured in `shared/server-common.nix`).

## Files to Change

| File | Change |
|------|--------|
| `shared/kubernetes.nix` | **Major rewrite** — all nodes master+worker, cfssl forced off on node2/3, sops SA key + API token, etcd `mkForce` overrides (Phase 3) |
| `shared/keepalived.nix` | **New** — VRRP VIP `192.168.0.10`, unicast, nopreempt, `/healthz` track script (Phase 2a) |
| `lib/mkServer.nix` | `kubeApiVIP`, `kubeNodeIPs` specialArgs |
| `flake.nix` | keepalived module in `kubeNode` |
| `shared/server-common.nix` | `api.kube` → VIP, `node1` → 192.168.0.2, firewall 6443 (+8888 on node1) |
| `shared/kube-cert-renew.nix` | Drop the ssh token sync (sops delivers it) |
| `secrets/secrets.yaml` | `k8s/sa.key`, `k8s/apitoken.secret` |
| `hosts/local/local.nix` | `api.kube` → VIP |
| `~/Documents/Kubernetes` | `longhorn-default`/`longhorn-retain` → 3 replicas; five manifests pinning `192.168.0.2` |

## Implementation Phases

### Phase 1: Preparation (no changes applied)

1. **Backup etcd** on node1:
   ```bash
   sudo ETCDCTL_API=3 etcdctl snapshot save /tmp/etcd-backup-$(date +%Y%m%d).db \
     --endpoints=https://127.0.0.1:2379 \
     --cacert=/var/lib/kubernetes/secrets/ca.pem \
     --cert=/var/lib/kubernetes/secrets/etcd.pem \
     --key=/var/lib/kubernetes/secrets/etcd-key.pem
   ```
2. **Backup Longhorn volumes** via Longhorn UI at NodePort 30506
3. **Record cluster state**:
   ```bash
   kubectl get nodes -o wide
   kubectl get pods -A
   kubectl get pv,pvc -A
   ```
4. **Back up CFSSL CA key**: copy `/var/lib/cfssl/ca-key.pem` from node1 to safe location

### Phase 2: Create keepalived module + update specialArgs

**2a. Create `shared/keepalived.nix`:**
```nix
{ config, pkgs, lib, ip, netInterface ? "eno1", kubeApiVIP, kubeNodeIPs, ... }:
let
  priority = { "192.168.0.2" = 101; "192.168.0.4" = 100; "192.168.0.6" = 99; }.${ip};
in {
  services.keepalived = {
    enable = true;
    openFirewall = true;                       # VRRP is IP proto 112, not a port
    enableScriptSecurity = true;
    vrrpInstances.kube-api = {
      interface = netInterface;
      state = "BACKUP";                        # nopreempt needs every node BACKUP
      virtualRouterId = 51;
      inherit priority;
      noPreempt = true;                        # a rebuild restart must not bounce the VIP
      unicastSrcIp = ip;
      unicastPeers = lib.filter (p: p != ip) kubeNodeIPs;
      virtualIps = [ { addr = "${kubeApiVIP}/24"; } ];
      trackScripts = [ "chk_apiserver" ];
    };
    vrrpScripts.chk_apiserver = {
      script = "${pkgs.curl}/bin/curl -sfk --max-time 2 https://127.0.0.1:6443/healthz";
      user = "root";                           # the module creates no keepalived_script user
      interval = 2; fall = 3; rise = 2; weight = -50;
    };
  };
}
```

**2b. Update `lib/mkServer.nix` specialArgs** (that is where `kubeMasterIP` lives today):
```nix
kubeMasterIP = "192.168.0.2";         # cfssl host, etcd cert CN — unchanged
kubeMasterHostname = "api.kube";      # now the VIP's name
kubeMasterAPIServerPort = 6443;
kubeApiVIP = "192.168.0.10";
kubeNodeIPs = [ "192.168.0.2" "192.168.0.4" "192.168.0.6" ];
```

Add `./shared/keepalived.nix` to `kubeNode` in `flake.nix`.

**2c. Update `shared/server-common.nix`:**
- extraHosts: `api.kube` → VIP; add `node1` → `192.168.0.2` (it becomes `masterAddress`)
- Firewall: 6443 on every node, 8888 (cfssl) on node1 only; etcd 2379/2380 via `services.etcd.openFirewall`

**2d. Secrets** (`secrets/secrets.yaml`, decrypted by each node's host key):
```bash
openssl genrsa -out sa.key 4096                      # k8s/sa.key
ssh node1 sudo cat /var/lib/cfssl/apitoken.secret    # k8s/apitoken.secret
```
In `shared/kubernetes.nix`:
```nix
sops.secrets."k8s/sa.key" = { owner = "kubernetes"; mode = "0400"; };
sops.secrets."k8s/apitoken.secret" = { owner = "root"; mode = "0400"; };
```

**2e. Also point at the VIP:** `hosts/local/local.nix:89` (`api.kube`), and the five
KubeServer manifests that embed `192.168.0.2` (`config/game-servers/{minecraft,valheim}`,
`config/openvpn`, `config/GOTG/{api,importer}`).

### Phase 3: Rewrite kubernetes.nix for multi-master

Replace `isMaster` conditional with all-nodes-are-master design:

```nix
{ config, pkgs, lib, hostname, ip, kubeMasterIP, kubeMasterHostname, kubeMasterAPIServerPort,
  kubeApiVIP, kubeNodeIPs, ... }:
let
  isCfsslHost = ip == kubeMasterIP;
  saKey = config.sops.secrets."k8s/sa.key".path;
in {
  environment.systemPackages = with pkgs; [ kompose kubectl kubernetes ];

  sops.secrets."k8s/sa.key" = { owner = "kubernetes"; mode = "0400"; };
  sops.secrets."k8s/apitoken.secret" = { mode = "0400"; };

  services.kubernetes = {
    roles = [ "master" "node" ];
    masterAddress = "node1";              # certmgr remote (cfssl) and etcd cert CN; NOT the VIP
    apiserverAddress = "https://${kubeMasterHostname}:${toString kubeMasterAPIServerPort}";  # VIP
    easyCerts = true;
    pki.cfsslAPIExtraSANs = lib.mkIf isCfsslHost ([ kubeMasterIP ] ++ kubeNodeIPs);

    apiserver = {
      securePort = kubeMasterAPIServerPort;
      advertiseAddress = ip;              # adds this node's IP to the apiserver AND etcd cert SANs
      bindAddress = "0.0.0.0";
      etcd.servers = lib.mkForce (map (n: "https://${n}:2379") kubeNodeIPs);
      extraSANs = [ kubeMasterHostname kubeApiVIP ] ++ kubeNodeIPs;
      extraOpts = "--allow-privileged=true";
      serviceAccountKeyFile = saKey;        # identical on every master, or tokens fail 2/3 of the time
      serviceAccountSigningKeyFile = saKey;
    };
    controllerManager.serviceAccountKeyFile = saKey;

    proxy.enable = true;
    addons.dns.enable = true;
    kubelet = {
      enable = true;
      nodeIp = ip;
      extraOpts = "--anonymous-auth=true";
    };
  };

  # cfssl only on node1; the others get the token from sops and the CA from
  # certmgr's trust-on-bootstrap against node1.
  services.cfssl.enable = lib.mkForce isCfsslHost;
  systemd.services.cfssl.preStart = lib.mkIf (!isCfsslHost) (lib.mkForce "");
  systemd.services.kube-certmgr-bootstrap.preStart = lib.mkIf (!isCfsslHost) (lib.mkBefore ''
    install -m 600 ${config.sops.secrets."k8s/apitoken.secret".path} \
      ${config.services.kubernetes.secretsPath}/apitoken.secret
  '');

  # pki.nix pins etcd to loopback at normal priority: mkForce is required for the
  # five URL lists. Never also set systemd.services.etcd.environment.
  services.etcd = {
    name = hostname;                      # default is masterAddress on every node
    listenClientUrls = lib.mkForce [ "https://127.0.0.1:2379" "https://${ip}:2379" ];
    listenPeerUrls = lib.mkForce [ "https://${ip}:2380" ];
    advertiseClientUrls = lib.mkForce [ "https://${ip}:2379" ];
    initialAdvertisePeerUrls = lib.mkForce [ "https://${ip}:2380" ];
    initialCluster = lib.mkForce (map (n: "node${n}=https://${n}:2380") [ ... ]);  # see Phase 4
    initialClusterState = "existing";     # "new" only for node1's first start
    openFirewall = true;
  };

  systemd.services.kube-controller-manager.serviceConfig = {
    Restart = "on-failure";
    StartLimitBurst = 5;
    StartLimitIntervalSec = 10;
  };
}
```

Removed from the first draft: `pki.certs.etcd.hosts = mkForce …` (`pki.certs` is
`types.attrs`, the override would discard the cert's `name`/`cert`/`key`), and the
`systemd.services.etcd.environment` `mkForce` (conflicts with `services.etcd.*`).
`shared/kube-cert-renew.nix` loses its ssh token sync; the sops copy replaces it.

### Phase 4: Rolling deployment — etcd migration (CRITICAL)

This is imperative and cannot be purely declarative. **Do not skip steps.**

**4.1. Deploy node1 first:**
- Set `initialClusterState = "new"` and `initialCluster` containing only node1
- `sudo nixos-rebuild switch --flake .#node1`
- Verify etcd:
  ```bash
  sudo ETCDCTL_API=3 etcdctl member list \
    --endpoints=https://192.168.0.2:2379 \
    --cacert=/var/lib/kubernetes/secrets/ca.pem \
    --cert=/var/lib/kubernetes/secrets/etcd.pem \
    --key=/var/lib/kubernetes/secrets/etcd-key.pem
  ```

**4.2. Add node2 as a learner (imperative on node1):**
```bash
sudo ETCDCTL_API=3 etcdctl member add node2 --learner \
  --peer-urls=https://192.168.0.4:2380 \
  --endpoints=https://192.168.0.2:2379 \
  --cacert=/var/lib/kubernetes/secrets/ca.pem \
  --cert=/var/lib/kubernetes/secrets/etcd.pem \
  --key=/var/lib/kubernetes/secrets/etcd-key.pem
```
A learner does not vote, so the 1-member cluster keeps serving while node2 syncs
(a voter added to a 1-member cluster stalls it until the new member starts). Deploy
node2 with `initialClusterState = "existing"` and the 2-entry `initialCluster`;
node2's `/var/lib/etcd` must be empty. Then promote once it has caught up:
```bash
sudo ETCDCTL_API=3 etcdctl member promote <node2-id> ...
```

> **WARNING:** between this promote and node3's, quorum is 2 of 2 — no fault
> tolerance. Do 4.3 in the same sitting.

**4.3. Add node3 the same way** (`member add node3 --learner`, deploy with the
3-entry `initialCluster`, `member promote`). Now 3 voters, quorum 2. Verify:
```bash
sudo ETCDCTL_API=3 etcdctl endpoint health --cluster ...
```

**4.4. Final deploy:**
Set all nodes to 3-node `initialCluster` with `initialClusterState = "existing"`. Rebuild all:
```bash
sudo nixos-rebuild switch --flake .#node1
sudo nixos-rebuild switch --flake .#node2
sudo nixos-rebuild switch --flake .#node3
```

**Rollback:** If etcd clustering fails at any step:
1. Stop etcd on new nodes: `sudo systemctl stop etcd`
2. Remove failed members on node1: `etcdctl member remove <ID>`
3. Revert kubernetes.nix to single-master config
4. Rebuild node1

### Phase 5: Certificate regeneration

1. Delete old CFSSL cert on node1 and restart:
   ```bash
   sudo rm /var/lib/cfssl/cfssl.pem /var/lib/cfssl/cfssl-key.pem /var/lib/cfssl/cfssl.csr
   sudo systemctl restart cfssl
   ```
2. Delete kubernetes certs on all nodes and restart certmgr:
   ```bash
   # On each node:
   sudo rm /var/lib/kubernetes/secrets/*.pem
   sudo systemctl restart certmgr
   ```
3. Verify etcd peer communication: `etcdctl endpoint health --cluster`
4. Verify API server via VIP: `curl -sk https://192.168.0.10:6443/healthz`

### Phase 6: Longhorn replica count upgrade

In `~/Documents/Kubernetes/`:

**longhorn/settings.yaml:**
```yaml
default-replica-count: "3"
```

**longhorn/storage-class.yaml:**
- `longhorn-default`: `numberOfReplicas: "3"`
- `longhorn-retain`: `numberOfReplicas: "3"`
- `longhorn-single`: stays at `"1"` (media/cost optimization)

Apply via Argo CD sync or `kubectl apply`.

### Phase 7: Failover verification

For each node (one at a time):
1. Shut down the node
2. Verify VIP migrates: `ping 192.168.0.10`
3. Verify `kubectl get nodes` works from remaining nodes
4. Verify pods reschedule to healthy nodes
5. Verify Longhorn volumes remain accessible
6. Bring node back up
7. Verify etcd member rejoins: `etcdctl member list`
8. Verify node becomes `Ready`: `kubectl get nodes`

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| etcd data loss during migration | Medium | Critical | Pre-migration snapshot backup (Phase 1) |
| 2-node etcd window (Phase 4, steps 2→3) | Certain | Medium | Move fast, have backup ready |
| easyCerts cert incompatibility | High | High | Systematic `mkForce` overrides on all cert configs |
| CFSSL single point of failure | Medium | Low | Certs valid 30 days; CA key backed up; can restore on any node |
| keepalived split-brain | Low | Medium | VRRP proven on single-subnet L2 networks |
| Longhorn volumes during API downtime | Low | Medium | Existing mounts continue working; only new attach/detach blocked |
| SA key rotation (sops `k8s/sa.key` replaced) | Low | High | Every SA token is invalidated; see docs/reboot-resilience-research.md §2. Never rotate casually; add the old key as a second `--service-account-key-file` via `extraOpts` for 24h |
| certmgr colon-SAN restart loop on 3 masters (#434442) | Medium | Low | kube-apiserver restarts every 30 min; patch `request.hosts` if it appears |

## Future Improvements

- **Hand-rolled PKI in `secrets/`, `easyCerts = false`** — what justinas/nixos-ha-kubernetes,
  misumisumi and starcraft66 all do. Removes cfssl, certmgr, `kube-cert-renew.nix`, the
  node1 renewal SPOF, the certmgr colon-SAN restart loop (nixpkgs #434442) and the
  etcd-before-cert race (#124037). Cost: generate CA, per-node apiserver/etcd server+peer
  certs, client certs once; renew by re-encrypting and `deploy-nodes`.
- **Longhorn `longhorn-default`/`longhorn-retain` to 3 replicas** (`default-replica-count`
  and the `longhorn` class are already 3). `longhorn-single` volumes (jellyfin-data,
  windrose, nitrox, scooter) stay pinned to node3 regardless.
- **External etcd snapshot timer** to the NAS.
- **kube-vip** only if the VIP no longer has to cover cfssl:8888; it elects through the
  API it fronts (Talos documents the same chicken-and-egg).

## Sources

nixpkgs `31ecbac` `pki.nix:48,146,180-198,356-367,386,394,404`, `default.nix:255,298-308,345-350`,
`apiserver.nix:465-474,500-548`; NixOS manual "Kubernetes" chapter; nixpkgs #59364, #124037,
#434442, PR #45670, PR #457523; justinas/nixos-ha-kubernetes; misumisumi/nixos-k8s-config;
Luukvdm/nixos-config (sops-delivered CA/token with easyCerts); kubernetes #22351 and
Wikimedia T329826 (per-master SA keys); kubeadm HA guide and ha-considerations.md
(keepalived `check_apiserver`); etcd v3.6 runtime-reconfiguration and learner docs.
