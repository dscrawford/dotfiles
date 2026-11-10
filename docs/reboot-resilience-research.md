# Reboot resilience for the cluster

*2026-09-02. ~120 sources plus live measurement on all three nodes. High confidence on
the four root causes (measured) and remedies; medium on the mdadm mechanism.*

## Summary

Rebooting all three nodes after the 2026-09-02 update caused a multi-hour outage that
was **not** the expected stale-attachment problem. Four faults stacked, and deleting
`VolumeAttachment`s touched none of them:

| # | Fault | Mechanism | Fix |
|---|---|---|---|
| 1 | node3's RAID6 never assembled | SAS disks appear 8 s **after** `local-fs.target`; udev's `mdadm --incremental` never ran; `nofail` let boot continue; Longhorn used the root fs as its "media" disk | `hosts/node3/storage.nix` |
| 2 | One pod stuck `Unauthorized` | certmgr renewed the service-account key at boot (30-day cycle); apiserver restarted with a new `kid`; a token minted in the 30 s window is unverifiable; kubelet doesn't re-mint on 401 | static SA key |
| 3 | Every Longhorn engine died at start | open-iscsi 2.1.11 → 2.1.12 dropped `node.session.conn_reopen_log_freq`; `iscsiadm` refused all existing node records | `27b5ba7`; `iscsid` preStart clears records (`shared/iscsi.nix`) |
| 4 | Pods recreated every ~30 s | Longhorn `auto-delete-pod-when-volume-detached-unexpectedly` reacting to #3 | Longhorn setting + #3 |

## 1. The RAID never assembles on boot

**Measured** on node3 after reboot: no `/proc/mdstat`, no `md_mod`/`raid456`, zero
`mdadm` journal entries; `udevadm info /dev/sda1` shows `ID_FS_TYPE=linux_raid_member`
but **no `MD_*`**. `local-fs.target` at 18:05:59, `[sda] Attached SCSI disk` at
18:06:07. A manual `mdadm --assemble --scan -v` found all six members, 37T, 14
replicas. Root-fs `/mnt/storage` held a valid `longhorn-disk.cfg` (UUID 86a48931…,
2026-03-17) and empty replica skeletons from 2026-06-04 and 2026-07-30: this happened on
every reboot, and Longhorn silently accepted the root fs.

**Why udev didn't fire (unproven).** `64-md-raid-assembly.rules` has four gates before
`IMPORT{program}=mdadm --incremental`, and an `add` event on a `linux_raid_member`
should pass them ([rules](https://github.com/md-raid-utilities/mdadm/blob/main/udev-md-raid-assembly.rules)).
So either mdadm exited non-zero (udev logs that only at debug) or the event was a
`change`. Similar: mdadm 4.5's silent failure without `md_mod`
([mdadm#246](https://github.com/md-raid-utilities/mdadm/issues/246)). NixOS loads
`md_mod raid456` only in the **initrd** under `boot.swraid.enable`
([swraid.nix](https://raw.githubusercontent.com/NixOS/nixpkgs/master/nixos/modules/tasks/swraid.nix));
see also [nixpkgs#196800](https://github.com/NixOS/nixpkgs/issues/196800),
[#210210](https://github.com/NixOS/nixpkgs/issues/210210). To settle it (root):
`udevadm test --action=add /sys/class/block/sda1 2>&1 | grep -iE 'mdadm|MD_|64-md'`.

**Removing the cfg doesn't help.** longhorn-manager's disk monitor regenerates a missing
`longhorn-disk.cfg` from the UUID in `node.status.diskStatus`, with no mount-point check
([disk_monitor.go](https://raw.githubusercontent.com/longhorn/longhorn-manager/master/controller/monitor/disk_monitor.go));
a disk goes NotReady only on UUID mismatch, duplicate fsid, or generation failure
([node_controller.go](https://raw.githubusercontent.com/longhorn/longhorn-manager/master/controller/node_controller.go)).
An immutable (`chattr +i`) empty mountpoint makes generation fail, even for root.

**Fix, now in `hosts/node3/storage.nix`:**

- `boot.swraid.mdadmConf` with `DEVICE partitions` and an explicit `ARRAY` line.
- `mpt3sas` in the initrd; `md_mod raid456` in `boot.kernelModules`.
- Oneshot `mdadm-assemble-storage` (retries 30 s) before `mnt-storage.mount`; fstab gets
  `x-systemd.requires=` it and `x-systemd.device-timeout=120s`.
- Keep `nofail`, but gate consumers: `RequiresMountsFor` on containerd and kubelet, plus
  `AssertPathIsMountPoint` on kubelet. `ConditionPathIsMountPoint` would skip silently
  and never retry ([systemd.unit(5)](https://man7.org/linux/man-pages/man5/systemd.unit.5.html));
  `fileSystems.<name>.depends` isn't honored ([nixpkgs#217179](https://github.com/NixOS/nixpkgs/issues/217179)).
- Activation: `chattr +i /mnt/storage` while it's not a mountpoint.
- One-off, so the safeguard bites, clear the root-fs copy hidden under the mount:
  `sudo mount --bind / /mnt/rootfs && sudo rm -rf /mnt/rootfs/mnt/storage/* && sudo chattr +i /mnt/rootfs/mnt/storage && sudo umount /mnt/rootfs`.
- Disable Longhorn scheduling on node3's default `/var/lib/longhorn` disk.

Never touch this array from a 7.0+ kernel while the nodes run 6.18 (superblock-padding
incompatibility, [writeup](https://www.technowizardry.net/2026/07/failure-to-launch-mdadm-edition)).

## 2. Service-account key rotation kills tokens

**Measured** on node1: certmgr persisted `service-account.pem` at 18:06:52, apiserver up
18:07:26. The stuck pod's token `kid` was `RBQX…`; JWKS held only `SVW6…`; log:
`invalid bearer token, invalid signature, no keys found`. One pod (176 errors);
recreating it fixed it.

**Why.** nixpkgs makes the SA key pair an ordinary certmgr cert (720h, `validMin` 72h)
whose renewal restarts kube-apiserver and kube-controller-manager
([kubernetes/default.nix](https://raw.githubusercontent.com/NixOS/nixpkgs/release-25.11/nixos/modules/services/cluster/kubernetes/default.nix)),
so the signing key changes monthly. The apiserver finds keys by `kid` and loads them only
at start ([jwt.go](https://raw.githubusercontent.com/kubernetes/kubernetes/master/pkg/serviceaccount/jwt.go),
[KEP-740](https://github.com/kubernetes/enhancements/blob/master/keps/sig-auth/740-service-account-external-signing/README.md)).
Kubelet re-mints at 80% TTL or 24h; **a 401 never triggers a re-mint**
([token_manager.go](https://raw.githubusercontent.com/kubernetes/kubernetes/master/pkg/kubelet/token/token_manager.go),
[k/k#138689](https://github.com/kubernetes/kubernetes/issues/138689)). kubeadm never
rotates this key ([kubeadm-certs](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-certs/)).
`--service-account-key-file` accepts multiple files
([reference](https://v1-33.docs.kubernetes.io/docs/reference/command-line-tools-reference/kube-apiserver/)).

**Fix:** a static, never-rotated signing key for `serviceAccountSigningKeyFile`,
`serviceAccountKeyFile` and `controllerManager.serviceAccountKeyFile`, keeping the old
certmgr cert in `--service-account-key-file` for ≥24h so existing tokens verify
([rotation order](https://github.com/kubernetes/kubernetes/issues/20165),
[Azure procedure](https://azure.github.io/azure-workload-identity/docs/topics/self-managed-clusters/service-account-key-rotation.html)).

Open: with 1h projected tokens the kubelet should have re-minted within ~48 min but
hadn't after 30+. If it recurs, check node3's kubelet log for `failed to fetch token`.

## 3. open-iscsi 2.1.12 rejects 2.1.11's node records

**Measured.** Engine log: `iSCSI ERROR: Unknown parameter name
node.session.conn_reopen_log_freq … /etc/iscsi/nodes/iqn.2019-10.io.longhorn:…`. node3
generation 22 had open-iscsi 2.1.11, 23 had 2.1.12; the parameter is in 2.1.11's
`iscsiadm` only, and was restored upstream on 2026-08-19
([open-iscsi#542](https://github.com/open-iscsi/open-iscsi/commit/8112cdd9514df076dc64ca3d4e85283aa701ce7e)).

**Fix:** `27b5ba7` carried #542 as an overlay and clears `/etc/iscsi/{nodes,send_targets}`
in `iscsid` preStart; the records are per-attach Longhorn metadata.

## 4. Longhorn's pod-deletion loop

**Measured.** `Engine of volume dead unexpectedly … faulted`, then `Deleted pod X so that
Kubernetes will handle remounting volume Y`, every ~30 s per workload; engines torn down
seconds after start. `auto-delete-pod-when-volume-detached-unexpectedly=false` stopped it.

Settings (Longhorn 1.10.1 [settings](https://longhorn.io/docs/1.10.1/references/settings/),
[maintenance](https://longhorn.io/docs/1.10.1/maintenance/maintenance/),
[node failure](https://longhorn.io/docs/1.10.1/high-availability/node-failure/)):

| Setting | Was | Recommend | Why |
|---|---|---|---|
| `node-down-pod-deletion-policy` | `do-nothing` | `delete-both-statefulset-and-deployment-pod` | else pods on a dead node stay Terminating and VAs never release |
| `node-drain-policy` | `block-if-contains-last-replica` | `allow-if-replica-is-stopped` | docs' advice for single-replica volumes; default blocks node3's drain forever |
| `auto-delete-pod-when-volume-detached-unexpectedly` | `false` (temporary) | `true` after recovery | only looped because of #3 |
| `auto-salvage` | `true` | keep | needed for `jellyfin-data` |

Auto-delete **skips cluster-network RWX consumers**, so Jellyfin and arr-stack aren't
restarted on ESTALE; `kube-stale-mount-recovery` stays the mechanism, with a mount-touching
liveness probe as the upstream complement ([best practices](https://longhorn.io/docs/1.10.1/best-practices/)).

After an ungraceful reboot: instance-manager pods are bare and left `Unknown`
([longhorn#2650](https://github.com/longhorn/longhorn/issues/2650)); deleting a
`VolumeAttachment` only triggers `ControllerUnpublish` and never touches data
([API](https://kubernetes.io/docs/reference/kubernetes-api/config-and-storage-resources/volume-attachment-v1/)),
but VA names are deterministic, so it only helps an otherwise-finished detach; Longhorn's
own tickets are in `volumeattachments.longhorn.io`
([KB](https://longhorn.io/kb/troubleshooting-volume-cannot-attach-due-to-orphan-pending-node-id-or-longhorn-ui-ad-ticket/)).
Never put `NoExecute` taints on a node with Longhorn pods lacking tolerations
([KB](https://longhorn.io/kb/troubleshooting-noexecute-taint-prevents-workloads-from-terminating/)).

Single-replica RWX on node3 is reboot-fragile by construction (no `strict-local` for RWX,
no auto-delete, [fast failover](https://longhorn.io/docs/1.10.1/high-availability/rwx-volume-fast-failover/)
needs a running replica): every node3 reboot is a `jellyfin-data` outage; aim for short
and clean.

## 5. Reboot orchestration (now `reboot-nodes`)

- **Never all three at once**: workers down first, control plane up first, wait for Ready
  and healthy `longhorn-system` ([Harvester KB](https://harvesterhci.io/kb/shutdown_and_restart_a_harvester_cluster/),
  [longhorn#4036](https://github.com/longhorn/longhorn/discussions/4036)).
- Per node: cordon, `kubectl drain --ignore-daemonsets --delete-emptydir-data --timeout=0`,
  reboot, wait Ready, uncordon, wait for volumes. With `allow-if-replica-is-stopped` a
  single-replica node drains once consumers are scaled to 0
  ([longhorn#2072](https://github.com/longhorn/longhorn/issues/2072)); scale Jellyfin
  first on node3.
- Reboot needed when `readlink /run/booted-system/{kernel,initrd,kernel-modules}` differs
  from `/run/current-system/…` ([auto-upgrade.nix](https://raw.githubusercontent.com/NixOS/nixpkgs/master/nixos/modules/tasks/auto-upgrade.nix));
  `deploy-nodes` reports it.
- kured stalls on Longhorn's PDB without the scale-down ([longhorn#4652](https://github.com/longhorn/longhorn/issues/4652)).
- Set kubelet `shutdownGracePeriod` / `shutdownGracePeriodCriticalPods` (default 0) so
  an unplanned reboot lets the CSI plugin unmount ([node shutdown](https://kubernetes.io/docs/concepts/cluster-administration/node-shutdown/)).

## Still open

- udev's `mdadm` exit status on node3 (command in §1).
- Whether `services.kubernetes.pki.certs.serviceAccount` can be overridden to stop
  certmgr's monthly apiserver restart.
- `shutdownGracePeriod` is not set yet.
