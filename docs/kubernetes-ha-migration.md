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

## Implementation (done 2026-10-30, not yet deployed)

Everything below is in the repo; nothing has touched a node. The imperative
etcd steps of the first draft are gone: a node joins the cluster from its own
systemd unit.

| Piece | Where |
|-------|-------|
| VIP | `shared/keepalived.nix` — VRRP 51, unicast with `check_unicast_src`, `nopreempt`, priority node1 > node2 > node3, `/healthz` track script as `keepalived_script`; VRRP accepted from the two peers only and dropped from the pod CIDR |
| etcd growth | `shared/kube-etcd-cluster.nix` — `ExecStartPre`: waits for certmgr's `etcd.pem`; empty data dir → removes a stale registration of this node, `member add --learner` against a reachable peer, writes `ETCD_INITIAL_CLUSTER` from the live member list to `/run/etcd/join.env`; `ExecStartPost`: repairs a legacy `etcd.local` peer URL, `member promote` once in sync (`TimeoutStartSec=20min`, the switch waits). 2379/2380 reachable from the two peers only, never from pods: any cert the cluster CA signed is etcd root |
| control plane | `shared/kubernetes.nix` — `roles = [master node]` everywhere, `masterAddress = 192.168.0.2` (cfssl), `apiserverAddress = https://api.kube:6443` (VIP), `advertiseAddress = ip`, SANs for VIP + all node IPs, `--etcd-servers` all three, cfssl `mkForce` off on node2/3 |
| shared secrets | `secrets/kube.yaml` (sops, recipients admin + node1-3): `sa_key` → `/run/secrets/kube_sa_key` for apiserver + controller-manager; `apitoken` → copied into node1's cfssl state at each cfssl start, symlinked as node2/3's certmgr token. node1 also keeps `--service-account-key-file=…/service-account.pem` so tokens from the old key stay valid |
| DNS | `api.kube → 192.168.0.10` in `shared/server-common.nix` and `hosts/local/local.nix` |
| tests | `tests/nix/kube-ha.bats` (config pins, one flake eval), `tests/nix/kube-etcd-join.bats` (join/promote scripts against a stub etcdctl) |
| reboot-nodes | waits for `etcd` active on the rebooted node (its post-start has promoted/updated it) before uncordon |

### Rollout — the manual steps

```bash
# 0. desktop still resolves api.kube to node1; keep it that way until node1 holds the VIP
cd ~/.local/dotfiles

# 1. snapshot etcd (node1; sudo password)
ssh -t node1 'sudo ETCDCTL_API=3 etcdctl snapshot save /var/lib/etcd-pre-ha.db \
  --endpoints=https://127.0.0.1:2379 --cacert=/var/lib/kubernetes/secrets/ca.pem \
  --cert=/var/lib/kubernetes/secrets/etcd.pem --key=/var/lib/kubernetes/secrets/etcd-key.pem'

# 2. node1 first (deploy-nodes already orders master first), then node2, node3.
#    Each switch: node1 — etcd renamed, listens on its IP, peer URL repaired, VIP up,
#    SA key swapped, apiserver cert re-issued with the new SANs;
#    node2/3 — certmgr issues the control-plane certs, etcd joins as a learner and
#    is promoted before the switch returns, apiserver/scheduler/controller-manager start.
deploy-nodes

# 3. point the desktop at the VIP
sudo nixos-rebuild switch --flake '.?submodules=1#local'
```

Verify:

```bash
ssh node1 'sudo etcdctl member list -w table --endpoints=https://127.0.0.1:2379 \
  --cacert=/var/lib/kubernetes/secrets/ca.pem --cert=/var/lib/kubernetes/secrets/etcd.pem --key=/var/lib/kubernetes/secrets/etcd-key.pem'
# three members, IS LEARNER false
ip -4 addr show to 192.168.0.10            # on the node holding the VIP
kubectl get --raw /healthz                 # via api.kube = VIP
kubectl -n kube-system get lease kube-controller-manager kube-scheduler -o wide
```

Failover test (one node at a time, node1 included): `reboot-nodes --force <node>`;
`kubectl get nodes` keeps working, the lease holder moves, VIP moves within ~6 s.

### Recovery notes

- A node whose `/var/lib/etcd` is lost re-joins on its own at boot (pre-start sees
  no `member` dir). Remove the stale member first: `etcdctl member remove <id>`.
- All three data dirs lost: write `/run/etcd/join.env` by hand on one node with
  `ETCD_INITIAL_CLUSTER=<that node only>` and `ETCD_INITIAL_CLUSTER_STATE=new`,
  restore the snapshot, then let the other two join.
- The sops `apitoken` is now the source of truth; re-encrypting a new one rotates
  it on all nodes at the next switch. Do **not** rotate `sa_key` casually
  (invalidates every token not also signed by node1's legacy key).

### Still to do

- Drop node1's extra `--service-account-key-file=…/service-account.pem` once every
  token minted under the old key is gone (projected tokens: ≤1 h; legacy Secret
  tokens: regenerate), so a leaked old key no longer verifies on node1.
- Longhorn `longhorn-default`/`longhorn-retain` classes to 3 replicas (KubeServer repo).
- Five KubeServer manifests pin `192.168.0.2`: `config/game-servers/{minecraft,valheim}`,
  `config/openvpn`, `config/GOTG/{api,importer}`.

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
