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
| CFSSL (CA) | node1 | node1 (unchanged — low-risk SPOF, certs valid 30 days) |
| Longhorn replicas | 2 | 3 for default/retain classes |

## Key Design Decisions

### VIP: keepalived (VRRP)
Lightweight, no Kubernetes dependency, no chicken-and-egg problem (unlike kube-vip which runs inside K8s). The VIP `192.168.0.10` floats to whichever healthy node has highest priority. Health check curls the local API server — if unhealthy, priority drops and VIP moves.

### All 3 nodes become master+worker
Controller-manager and scheduler already support leader election (`leaderElect = true` is the default in the NixOS module). Only one instance leads at a time; the others are standby.

### easyCerts kept but overridden
Upstream NixOS `pki.nix` doesn't officially support multi-master (comment on line ~357: "easyCerts doesn't support multimaster clusters anyway atm"). We keep `easyCerts = true` but systematically override defaults with `lib.mkForce` where needed (etcd listen addresses, cert SANs, etc.).

### CFSSL stays on node1
CFSSL is the CA server that issues certs. It remains a SPOF, but certs are valid ~30 days — if node1 dies, existing certs keep working. The CA key (`/var/lib/cfssl/ca-key.pem`) must be backed up.

## Files to Change

| File | Change |
|------|--------|
| `shared/kubernetes.nix` | **Major rewrite** — remove `isMaster` conditional, all nodes master+worker, etcd clustering, cert SAN overrides |
| `shared/keepalived.nix` | **New** — VRRP floating VIP `192.168.0.10` with API server health checks |
| `flake.nix` | Add `kubeApiVIP`/`cfsslHostIP` specialArgs, add keepalived to all nodes |
| `shared/server-common.nix` | Point `api.kube` at VIP, add etcd ports 2379/2380 to firewall |
| `~/Documents/Kubernetes/longhorn/settings.yaml` | `default-replica-count: "3"` |
| `~/Documents/Kubernetes/longhorn/storage-class.yaml` | `numberOfReplicas: "3"` for default + retain classes |

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
{ config, pkgs, lib, ip, netInterface ? "eno1", ... }:
let
  vip = "192.168.0.10";
  priorityMap = {
    "192.168.0.2" = 101;  # node1 — preferred VIP holder
    "192.168.0.4" = 100;  # node2
    "192.168.0.6" = 99;   # node3
  };
  priority = priorityMap.${ip};
in {
  services.keepalived.enable = true;
  services.keepalived.vrrpInstances.kube-api = {
    interface = netInterface;
    state = if priority == 101 then "MASTER" else "BACKUP";
    virtualRouterId = 51;
    priority = priority;
    virtualIps = [{ addr = "${vip}/24"; }];
    trackScripts = ["chk_apiserver"];
  };
  services.keepalived.vrrpScripts.chk_apiserver = {
    script = "${pkgs.curl}/bin/curl -sk https://127.0.0.1:6443/healthz";
    interval = 2;
    weight = -50;  # drop priority if API server unhealthy
  };
  networking.firewall.extraCommands = "iptables -A INPUT -p vrrp -j ACCEPT";
}
```

**2b. Update `flake.nix` specialArgs:**
```nix
specialArgs = {
  inherit hostname ip netInterface;
  kubeMasterIP = "192.168.0.2";         # CFSSL host (unchanged)
  kubeApiVIP = "192.168.0.10";          # NEW: floating VIP
  cfsslHostIP = "192.168.0.2";          # NEW: explicit CFSSL location
  kubeMasterHostname = "api.kube";
  kubeMasterAPIServerPort = 6443;
};
```

Add `./shared/keepalived.nix` to all 3 nodes' `extraModules`.

**2c. Update `shared/server-common.nix`:**
- Change extraHosts: point `api.kube` at VIP (`192.168.0.10`) instead of `192.168.0.2`
- Add etcd ports to firewall: `2379` (client), `2380` (peer)
- Add `kubeApiVIP` to function params
- Remove unused `isMaster` from function params (if present)

### Phase 3: Rewrite kubernetes.nix for multi-master

Replace `isMaster` conditional with all-nodes-are-master design:

```nix
{ config, pkgs, lib, hostname, ip, kubeMasterIP, kubeMasterHostname, kubeMasterAPIServerPort, ... }:
let
  allNodes = {
    node1 = "192.168.0.2";
    node2 = "192.168.0.4";
    node3 = "192.168.0.6";
  };
  allNodeIPs = lib.attrValues allNodes;
  kubeApiVIP = "192.168.0.10";
  isCfsslHost = ip == "192.168.0.2";
in {
  environment.systemPackages = with pkgs; [ kompose kubectl kubernetes ];

  services.kubernetes = {
    roles = [ "master" "node" ];
    masterAddress = kubeMasterHostname;
    apiserverAddress = "https://${kubeMasterHostname}:${toString kubeMasterAPIServerPort}";
    easyCerts = true;
    pki.cfsslAPIExtraSANs = lib.mkIf isCfsslHost (allNodeIPs ++ [ kubeApiVIP ]);

    apiserver = {
      securePort = kubeMasterAPIServerPort;
      advertiseAddress = ip;  # Each API server advertises its own IP
      bindAddress = "0.0.0.0";
      etcd.servers = lib.mkForce (map (nodeIP: "https://${nodeIP}:2379") allNodeIPs);
      extraSANs = [ kubeMasterHostname kubeApiVIP ] ++ allNodeIPs;
      extraOpts = "--allow-privileged=true";
    };

    proxy.enable = true;
    addons.dns.enable = true;
    kubelet = {
      enable = true;
      nodeIp = ip;
      extraOpts = "--anonymous-auth=true";
    };
  };

  # Override etcd cert SANs to include all node IPs
  services.kubernetes.pki.certs.etcd.hosts = lib.mkForce ([
    "etcd.local" "etcd.cluster.local" kubeMasterHostname kubeApiVIP
  ] ++ allNodeIPs);

  # etcd clustering — override easyCerts loopback defaults
  services.etcd = {
    name = lib.mkForce hostname;
    listenClientUrls = lib.mkForce [ "https://127.0.0.1:2379" "https://${ip}:2379" ];
    listenPeerUrls = lib.mkForce [ "https://${ip}:2380" ];
    advertiseClientUrls = lib.mkForce [ "https://${ip}:2379" ];
    initialAdvertisePeerUrls = lib.mkForce [ "https://${ip}:2380" ];
    initialCluster = lib.mkForce [
      "node1=https://192.168.0.2:2380"
      "node2=https://192.168.0.4:2380"
      "node3=https://192.168.0.6:2380"
    ];
    initialClusterToken = lib.mkForce "kube-etcd-cluster";
    initialClusterState = lib.mkForce "existing";  # Toggle during migration
    openFirewall = true;
  };

  systemd.services.kube-controller-manager.serviceConfig = {
    Restart = "on-failure";
    StartLimitBurst = 5;
    StartLimitIntervalSec = 10;
  };
}
```

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

**4.2. Add node2 to etcd (imperative on node1):**
```bash
sudo ETCDCTL_API=3 etcdctl member add node2 \
  --peer-urls=https://192.168.0.4:2380 \
  --endpoints=https://192.168.0.2:2379 \
  --cacert=/var/lib/kubernetes/secrets/ca.pem \
  --cert=/var/lib/kubernetes/secrets/etcd.pem \
  --key=/var/lib/kubernetes/secrets/etcd-key.pem
```
Then deploy node2 with `initialClusterState = "existing"` and 2-node `initialCluster`.

> **WARNING:** 2-node etcd has NO fault tolerance (quorum=2). Proceed immediately to step 4.3.

**4.3. Add node3 to etcd (same procedure):**
```bash
sudo ETCDCTL_API=3 etcdctl member add node3 \
  --peer-urls=https://192.168.0.6:2380 ...
```
Deploy node3. Now 3-node cluster with quorum=2. Verify:
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

## Future Improvements

- **Distribute CFSSL CA key** to all nodes so any node can run the CA server
- **Move to kubeadm or k3s** for proper multi-master support without easyCerts workarounds
- **Add external etcd backup cronjob** for automated disaster recovery
- **Consider kube-vip** once the cluster is stable (replaces keepalived, runs as static pod)
