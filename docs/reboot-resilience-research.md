# Reboot resilience for the cluster: research report

*Generated: 2026-09-02 | Sources: ~120 across three research passes plus live measurement on all three nodes | Confidence: High on the four root causes (all measured), Medium on the mdadm mechanism (needs one root-run udev test), High on the remedies (upstream docs/code)*

## Executive summary

Rebooting all three nodes after the 2026-09-02 fleet update produced a multi-hour
outage that was **not** the "stale attachment" problem the runbook expects. Four
independent faults stacked, and the usual fix (deleting `VolumeAttachment`s)
could not touch any of them:

| # | Fault | Mechanism | Fix class |
|---|---|---|---|
| 1 | node3's RAID6 never assembled | SAS disks appear 8 s **after** `local-fs.target`; udev's `mdadm --incremental` never ran; `nofail` let boot continue; Longhorn used the root fs as its "media" disk | config (this repo) |
| 2 | One pod stuck `Unauthorized` forever | certmgr renewed the service-account key at boot (30-day cycle); apiserver restarted with a new `kid`; a token minted in the 30 s window is unverifiable; kubelet does not re-mint on 401 | config (this repo) |
| 3 | Every Longhorn engine died at start | open-iscsi 2.1.11 to 2.1.12 dropped `node.session.conn_reopen_log_freq`; `iscsiadm` refused all pre-existing node records | fixed: `27b5ba7` |
| 4 | Pods recreated every ~30 s | Longhorn `auto-delete-pod-when-volume-detached-unexpectedly` reacting to #3 | Longhorn setting plus #3 |

Everything below is either measured on the nodes today or cited.

## 1. The RAID never assembles on boot

**Measured.** After reboot on node3: `/proc/mdstat` absent, no `md_mod`/`raid456`
loaded, zero `mdadm` journal entries, `udevadm info /dev/sda1` shows
`ID_FS_TYPE=linux_raid_member` but **no `MD_*` properties**. `local-fs.target`
reached 18:05:59; `sd 10:0:0:0: [sda] Attached SCSI disk` 18:06:07.
`mdadm --assemble --scan -v` run by hand later: all six members found, clean
start, 37T mounted, 14 replicas present. Root-fs `/mnt/storage` held a valid
`longhorn-disk.cfg` (UUID 86a48931..., dated 2026-03-17) and eight empty replica
skeletons from 2026-06-04 and 2026-07-30, i.e. this has happened on every
reboot, and Longhorn has been silently accepting the root fs each time.

**Why udev did not fire (ranked, not proven).** The installed
`64-md-raid-assembly.rules` has only four gates before `IMPORT{program}=mdadm
--incremental --export ...`; a device with `ID_FS_TYPE=linux_raid_member` on an
`add` event should reach it
([mdadm rules](https://github.com/md-raid-utilities/mdadm/blob/main/udev-md-raid-assembly.rules)).
`SYSTEMD_READY=0` is only set for md/dm/crypt devices, not SAS partitions
([99-systemd.rules](https://raw.githubusercontent.com/systemd/systemd/main/rules.d/99-systemd.rules.in)).
So either mdadm ran and exited non-zero (udev imports nothing and logs only at
debug), or the event was a `change` (excluded by the rule). The closest known
failure class is mdadm 4.5's "md_mod not loaded, incremental fails silently"
([mdadm#246](https://github.com/md-raid-utilities/mdadm/issues/246), fixed in 4.6
which node3 runs), same symptom shape. NixOS only loads `md_mod raid456` in the
**initrd** when `boot.swraid.enable` is on
([swraid.nix](https://raw.githubusercontent.com/NixOS/nixpkgs/master/nixos/modules/tasks/swraid.nix));
nothing guarantees they are loaded in stage 2 before late disks appear. Related
open nixpkgs issues: [#196800](https://github.com/NixOS/nixpkgs/issues/196800)
(mdadm does not start at boot since systemd 251; workaround: explicit `ARRAY`
lines), [#210210](https://github.com/NixOS/nixpkgs/issues/210210).

**One-command settle (needs root, once):**
`udevadm test --action=add /sys/class/block/sda1 2>&1 | grep -iE 'mdadm|MD_|64-md'`
prints whether the rule is reached and mdadm's exit status.

**The dangerous half is Longhorn, and removing the cfg does not help.** Reading
longhorn-manager's disk monitor: on "config not found" it **regenerates**
`longhorn-disk.cfg` using the UUID already in `node.status.diskStatus`, and there
is no mount-point check
([disk_monitor.go](https://raw.githubusercontent.com/longhorn/longhorn-manager/master/controller/monitor/disk_monitor.go)).
A disk goes NotReady only on UUID mismatch, fsid duplicate with another Ready
disk, or config-generation failure
([node_controller.go](https://raw.githubusercontent.com/longhorn/longhorn-manager/master/controller/node_controller.go)).
So the safeguard has to make generation *fail*: an immutable (`chattr +i`) empty
mountpoint does exactly that, and the kernel honors it even for root.

**Fix (node3):**

- `boot.swraid.mdadmConf`: `DEVICE partitions` plus `ARRAY /dev/md0 metadata=1.2 UUID=<from mdadm --detail>` for deterministic assembly
  ([mdadm.conf(5)](https://man7.org/linux/man-pages/man5/mdadm.conf.5.html)).
- `boot.initrd.availableKernelModules = [ "mpt3sas" ]` so SAS discovery starts in stage 1; `boot.kernelModules = [ "md_mod" "raid456" ]` so stage 2 has the personalities before the disks arrive.
- A `Type=oneshot` `mdadm-assemble-storage` unit (`mdadm --assemble --scan --uuid=...`, retried for 30 s, idempotent) ordered `before = [ "mnt-storage.mount" ]`; the fstab entry gains `x-systemd.requires=mdadm-assemble-storage.service` and `x-systemd.device-timeout=120s`
  ([systemd.mount(5)](https://man7.org/linux/man-pages/man5/systemd.mount.5.html), [45Drives pattern](https://knowledgebase.45drives.com/kb/kb450304-assembling-rbd-mdadm-raids-on-boot/)).
- **Keep `nofail`** (node stays bootable and reachable) but move the hard gate to the consumers: `systemd.services.{containerd,kubelet}.unitConfig.RequiresMountsFor = [ "/mnt/storage" ]` plus `AssertPathIsMountPoint=/mnt/storage` on kubelet. `ConditionPathIsMountPoint` would be wrong: it silently skips and never retries
  ([systemd.unit(5)](https://man7.org/linux/man-pages/man5/systemd.unit.5.html)). Note `fileSystems.<name>.depends` is not honored ([nixpkgs#217179](https://github.com/NixOS/nixpkgs/issues/217179)).
- Activation script: `chattr +i /mnt/storage` while it is not a mountpoint.
- Longhorn: disable scheduling on node3's default `/var/lib/longhorn` disk so a replica can never land on the root fs.

**Caveat:** the 2026-07 kernel 7.0 superblock-padding incompatibility
([writeup](https://www.technowizardry.net/2026/07/failure-to-launch-mdadm-edition))
means never touch this array from a 7.0+ kernel while the nodes run 6.18.

## 2. Service-account key rotation kills tokens

**Measured.** node1 certmgr: `persisting PKI ... cert=/var/lib/kubernetes/secrets/service-account.pem` at 18:06:52; apiserver active 18:07:26. The stuck pod's token `kid` was `RBQX...`; the apiserver JWKS held only `SVW6...`; apiserver log: `invalid bearer token, invalid signature, no keys found`. Exactly one pod affected (176 errors); recreating it fixed it.

**Why.** nixpkgs' module makes the SA key pair an ordinary certmgr cert whose renewal action is `systemctl restart kube-apiserver kube-controller-manager`
([kubernetes/default.nix](https://raw.githubusercontent.com/NixOS/nixpkgs/release-25.11/nixos/modules/services/cluster/kubernetes/default.nix)),
with 720h validity and certmgr's 72h `validMin`, so the signing key changes roughly monthly, by design. The apiserver looks keys up by `kid` = sha256(public key); a token whose `kid` is absent fails with "no keys found"
([jwt.go](https://raw.githubusercontent.com/kubernetes/kubernetes/master/pkg/serviceaccount/jwt.go)).
Keys load once at process start; rotation requires a restart
([KEP-740](https://github.com/kubernetes/enhancements/blob/master/keps/sig-auth/740-service-account-external-signing/README.md)).
Kubelet re-mints only at 80% of TTL or 24h; **a 401 never triggers a re-mint**
([token_manager.go](https://raw.githubusercontent.com/kubernetes/kubernetes/master/pkg/kubelet/token/token_manager.go),
[k/k#138689](https://github.com/kubernetes/kubernetes/issues/138689)).
kubeadm deliberately never rotates this key
([kubeadm-certs](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-certs/)).
`--service-account-key-file` accepts multiple files and multi-block PEM
([kube-apiserver reference](https://v1-33.docs.kubernetes.io/docs/reference/command-line-tools-reference/kube-apiserver/),
[keyutil](https://raw.githubusercontent.com/kubernetes/client-go/master/util/keyutil/key.go)).

**Fix (node1):** a static, never-rotated signing key generated once by a oneshot;
`serviceAccountSigningKeyFile`, `serviceAccountKeyFile` and
`controllerManager.serviceAccountKeyFile` forced to it; during migration
`extraOpts = "--service-account-key-file=<current certmgr cert>"` for at least 24h so existing tokens keep verifying
([documented rotation order](https://github.com/kubernetes/kubernetes/issues/20165),
[Azure procedure](https://azure.github.io/azure-workload-identity/docs/topics/self-managed-clusters/service-account-key-rotation.html)).
Then drop the extra key. Unverified: whether `services.kubernetes.pki.certs.serviceAccount` can be overridden to stop certmgr's now-pointless monthly apiserver restart; test with `nixos-rebuild build`.

**Open question the research could not answer:** with default 1h projected tokens the kubelet should have re-minted within ~48 min. It had not after 30+ min; check node3's kubelet log for `failed to fetch token` if it recurs.

## 3. open-iscsi 2.1.12 rejects 2.1.11's node records

**Measured.** Engine log: `failed to start up frontend: ... iscsiadm -m node ... -o show ... iSCSI ERROR: Unknown parameter name node.session.conn_reopen_log_freq (libopeniscsiusr/idbm.c) ... config file /etc/iscsi/nodes/iqn.2019-10.io.longhorn:...`. node3 generations: 22 = open-iscsi 2.1.11, 23 = 2.1.12. Binary grep: the 2.1.11 `iscsiadm` contains the parameter, 2.1.12 does not. Upstream: present at tag 2.1.11, absent at tag 2.1.12 (2026-07-15), restored on master 2026-08-19 by "Fix reopen log freq change" ([open-iscsi#542](https://github.com/open-iscsi/open-iscsi/commit/8112cdd9514df076dc64ca3d4e85283aa701ce7e)).

**Fix:** `27b5ba7`, an overlay carrying #542 (11-line patch, applies cleanly to nixpkgs' 2.1.12; the built `iscsiadm` contains the parameter) plus `rm -rf /etc/iscsi/{nodes,send_targets}/*` in `iscsid` `preStart`. The records are per-attach Longhorn metadata; nothing else uses the initiator.

## 4. Longhorn's reaction: the pod-deletion loop

**Measured.** longhorn-manager: `Engine of volume dead unexpectedly, setting v.Status.Robustness to faulted`, then `Deleted pod X so that Kubernetes will handle remounting volume Y` (KubernetesPodController), every ~30 s per workload, ~8 ReplicaSet creations per 5 min, engines torn down mid-start ("prepare to delete process" seconds after "Creating process"). Setting `auto-delete-pod-when-volume-detached-unexpectedly=false` stopped it instantly.

**Settings worth changing** (Longhorn 1.10.1 docs:
[settings](https://longhorn.io/docs/1.10.1/references/settings/),
[maintenance](https://longhorn.io/docs/1.10.1/maintenance/maintenance/),
[node failure](https://longhorn.io/docs/1.10.1/high-availability/node-failure/)):

| Setting | Now | Recommend | Why |
|---|---|---|---|
| `node-down-pod-deletion-policy` | `do-nothing` | `delete-both-statefulset-and-deployment-pod` | with `do-nothing`, pods on a dead node stay Terminating forever and VAs never release |
| `node-drain-policy` | `block-if-contains-last-replica` | `allow-if-replica-is-stopped` | the docs' explicit advice for single-replica volumes; the default blocks node3's drain forever |
| `auto-delete-pod-when-volume-detached-unexpectedly` | `false` (temporary) | back to `true` after recovery | useful in the normal case; it only looped because #3 made every attach fail |
| `auto-salvage` | `true` | keep | needed for `jellyfin-data` after node3 returns |

The auto-delete safety net **does not apply to cluster-network RWX consumers**
(settings doc), so Jellyfin and arr-stack will not be restarted for you on ESTALE;
the existing `kube-stale-mount-recovery` sweep remains the mechanism, and a
liveness probe touching the mount is the upstream-recommended complement
([best practices](https://longhorn.io/docs/1.10.1/best-practices/)).

Stale objects after an ungraceful reboot, with upstream backing: instance-manager
pods are bare pods, never rescheduled, left `Unknown`
([longhorn#2650](https://github.com/longhorn/longhorn/issues/2650),
[#5809](https://github.com/longhorn/longhorn/issues/5809)); `VolumeAttachment`
is metadata only, deletion triggers `ControllerUnpublish` and never touches data
([VolumeAttachment API](https://kubernetes.io/docs/reference/kubernetes-api/config-and-storage-resources/volume-attachment-v1/),
[k/k#67853](https://github.com/kubernetes/kubernetes/issues/67853)). Note that
Kubernetes regenerates VA names deterministically, so deleting one only helps a
detach that is otherwise finished; Longhorn's own tickets live in
`volumeattachments.longhorn.io`
([KB](https://longhorn.io/kb/troubleshooting-volume-cannot-attach-due-to-orphan-pending-node-id-or-longhorn-ui-ad-ticket/)).
Never put `NoExecute` taints on a node with Longhorn pods lacking tolerations
([KB](https://longhorn.io/kb/troubleshooting-noexecute-taint-prevents-workloads-from-terminating/)).

Single-replica RWX on node3's RAID is reboot-fragile by construction: RWX
cannot use `strict-local`, the auto-delete net excludes it, and RWX fast
failover still needs a running replica somewhere
([fast failover](https://longhorn.io/docs/1.10.1/high-availability/rwx-volume-fast-failover/)).
Any node3 reboot is a full `jellyfin-data` outage; the goal is to make it a
*short, clean* one.

## 5. Reboot orchestration

- **Never all three at once.** Harvester (SUSE, Longhorn-based): workers down first, control plane up first, wait for Ready and healthy `longhorn-system` before workloads ([Harvester KB](https://harvesterhci.io/kb/shutdown_and_restart_a_harvester_cluster/)); Longhorn maintainers: detach all volumes before a cluster shutdown ([discussion#4036](https://github.com/longhorn/longhorn/discussions/4036)).
- Per node: cordon, `kubectl drain --ignore-daemonsets --delete-emptydir-data --timeout=0`, reboot, wait Ready, uncordon, wait for volumes healthy. Longhorn enforces drain safety with a PDB on instance-manager; with `allow-if-replica-is-stopped` a single-replica node drains once its consumers are scaled to 0 ([longhorn#2072](https://github.com/longhorn/longhorn/issues/2072)).
- For node3: scale Jellyfin (and other `jellyfin-data` consumers) to 0 first.
- "Reboot needed" detection: compare `readlink /run/booted-system/{kernel,initrd,kernel-modules}` with `/run/current-system/...`, the same test `system.autoUpgrade` uses ([auto-upgrade.nix](https://raw.githubusercontent.com/NixOS/nixpkgs/master/nixos/modules/tasks/auto-upgrade.nix)); `deploy-nodes` already reports this per node.
- kured automates one-at-a-time drain and reboot but stalls on Longhorn's PDB without the scale-down step, and upstream will not change that ([longhorn#4652](https://github.com/longhorn/longhorn/issues/4652)); no NixOS packaging found. Extending `deploy-nodes --reboot` with the sequence above is the better fit here.
- Configure kubelet `shutdownGracePeriod` and `shutdownGracePeriodCriticalPods` (currently default 0, disabled) so an unplanned reboot still lets the CSI plugin unmount ([node shutdown](https://kubernetes.io/docs/concepts/cluster-administration/node-shutdown/)).

## Key takeaways

1. Today's outage had four causes; the attachment-deletion runbook addressed none of them. #3 is fixed in this repo; #1, #2 and the Longhorn settings are designed above and ready to implement.
2. The root-fs-as-Longhorn-disk hazard is real and has recurred on every reboot since March; it needs the immutable mountpoint and the kubelet gate, not just a working `mdadm`.
3. Reboot one node at a time, control plane first on the way up, with node3's RWX consumers scaled down, and let `deploy-nodes` drive it.
4. Two things still need one root-run measurement each: the udev `mdadm` exit status on node3, and whether `pki.certs.serviceAccount` can be overridden cleanly.

## Sources

Consolidated from the three research passes; every URL above is a source. Longhorn docs 1.10.1 (settings, maintenance, node-failure, RWX, fast-failover, multidisk, node-conditions, best-practices, KBs); longhorn-manager source (disk_monitor.go, node_controller.go); longhorn issues #2650, #5809, #2072, #4652, #4036, #12485, #12319, #11876, #6655; Kubernetes docs and KEPs (VolumeAttachment API, projected volumes, node shutdown, kubeadm-certs, KEP-740, KEP-1205) and source (jwt.go, token_manager.go, keyutil); k/k issues #20165, #91070, #67853, #138689; nixpkgs modules (swraid.nix, kubernetes/default.nix, pki.nix, apiserver.nix, certmgr.nix, auto-upgrade.nix) and issues #196800, #210210, #217179; mdadm rules/units, man pages mdadm(8) and mdadm.conf(5), mdadm#246; systemd man pages systemd.mount(5), systemd.unit(5), systemd.device(5); open-iscsi#542; Harvester KB; kured docs.

## Methodology

Three parallel research agents (mdadm and mount gating; SA-key rotation; Longhorn recovery and reboot orchestration), WebSearch and WebFetch only, ~120 unique sources, 12-month recency preferred, single-source claims flagged in the agent transcripts. Every mechanism claim was then checked against live state on node1 to node3 (journals, udev DB, Longhorn CRs and logs, instance-manager logs, binary greps of both open-iscsi store paths, upstream git tags). The open-iscsi finding post-dates the agents and was established entirely from local evidence plus upstream git.
