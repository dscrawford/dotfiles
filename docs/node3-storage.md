# Node3 Storage: mdadm RAID6

Two arrays today, one by the end of the migration below. Both are declared in
`hosts/node3/storage.nix`; this file holds the one-off commands and the plan.

## Layout

| Array | Drives | Filesystem | Mount | Longhorn disk |
|-------|--------|------------|-------|---------------|
| `md0` | 6x WDC WD100EMAZ 10TB (RAID6, ~36 TiB) | ext4 | `/mnt/storage` | `media` (being emptied) |
| `md1` | 4x HGST HUH721010ALE600 10TB (RAID6, ~18 TiB) | xfs | `/mnt/data` | `data` |

Drives are addressed by WWN (`/dev/disk/by-id/wwn-*`); `sdX` names move
between boots and hot-swaps. HGST serials and WWNs:

| Serial | WWN | Note |
|--------|-----|------|
| JEG6HV6N | `wwn-0x5000cca267c2f5b5` | md1 |
| JEGGRWAN | `wwn-0x5000cca267c6b317` | md1 |
| JEGH3L0X | `wwn-0x5000cca267c6df02` | md1 |
| JEGGZT5X | `wwn-0x5000cca267c6d0bd` | md1 |
| JEGG8TWN | `wwn-0x5000cca267c67e3d` | DOA 2026-11-10: no link on two controllers; RMA |

Why xfs: a Longhorn replica is one sparse file per snapshot, sized to the
volume, and ext4 caps a file at 16 TiB. `jellyfin-data` hit that cap on `md0`.
Longhorn also needs FIEMAP on the disk filesystem, which rules out ZFS
datasets; btrfs is unsupported.

Controllers: a SAS9305-16i (`host0`, dock row 3) and an LSI SAS3008 (`host11`,
rows 1-2, phys 0-3 and 4-7 are the two cables). `cat /sys/class/sas_phy/*/`
counters tell a bad link from a bad drive.

## Creating an array

Partition each drive (one GPT partition), then create, format, and read the
identifiers `storage.nix` needs:

```bash
printf 'label: gpt\ntype=linux\n' | sfdisk --quiet /dev/disk/by-id/wwn-...
mdadm --create /dev/md1 --level=6 --raid-devices=4 --name=storage2 /dev/disk/by-id/wwn-...-part1 ...
nix shell nixpkgs#xfsprogs -c mkfs.xfs -L storage2 /dev/md1
mdadm --detail --scan        # ARRAY line: arrayUUID
blkid -o export /dev/md1     # UUID=...: fsUUID
```

The initial sync (`cat /proc/mdstat`) takes 14-18 h for 10 TB drives; the
array is usable immediately. Apply the config with `nixos-rebuild boot` rather
than `switch`: the `RequiresMountsFor` change would restart containerd and
kubelet live. Mount by hand until the next reboot.

## Migration md0 (ext4) -> md1 (xfs), then grow md1

1. Add `/mnt/data` to the Longhorn node as disk `data`. The nominal size
   of the replicas on `media` (~17 TiB) exceeds what Longhorn will schedule on
   an 18 TiB disk at the defaults, so for the migration set
   `storage-minimal-available-percentage` to 5 and
   `storage-over-provisioning-percentage` to 150, and turn on
   `offline-replica-rebuilding` so detached volumes move too.
2. Evict `media` (`evictionRequested: true` on the disk). Longhorn rebuilds
   each replica onto `data`, online. 10-20 h for ~14 TiB.
3. Gate: `media` reports 0 replicas and `/mnt/storage/replicas` is empty.
   Only then: remove `media` from the Longhorn node, unmount `/mnt/storage`,
   `mdadm --stop /dev/md0`, `wipefs -a` the six WD partitions.
4. Grow `md1` in one reshape with every drive at hand (the WDs plus the HGST
   replacement), then the filesystem:

   ```bash
   mdadm /dev/md1 --add /dev/disk/by-id/wwn-...-part1 ...
   mdadm --grow /dev/md1 --raid-devices=11
   cat /proc/mdstat              # reshape, 1.5-4 days, online
   xfs_growfs /mnt/data
   ```

5. Drop the `storage` entry from `storage.nix`, restore the Longhorn settings,
   expand `jellyfin-data`, reboot once to prove boot-time assembly.

## Adding a drive later

Same as step 4 with one drive: `--add`, `--grow --raid-devices=N+1`,
`xfs_growfs`. Each reshape rewrites every stripe; batch drives when possible.

## Replacing a failed drive

```bash
cat /proc/mdstat; mdadm --detail /dev/md1
mdadm /dev/md1 --fail /dev/disk/by-id/wwn-FAILED-part1
mdadm /dev/md1 --remove /dev/disk/by-id/wwn-FAILED-part1
# swap the drive, partition it as above, then
mdadm /dev/md1 --add /dev/disk/by-id/wwn-NEW-part1
```

Rebuild starts automatically. Mixed sizes: an array uses the smallest member's
size, so partition a larger drive down to 10 TB (`sfdisk` with `size=`).

## Useful commands

```bash
cat /proc/mdstat                               # sync/reshape/rebuild progress
mdadm --detail /dev/md1
for p in /sys/class/sas_phy/*; do echo "$p $(cat $p/negotiated_linkrate) inv=$(cat $p/invalid_dword_count)"; done
nix shell nixpkgs#smartmontools -c smartctl -H -l error /dev/disk/by-id/wwn-...
xfs_repair -n /dev/md1                         # check only; unmount first for a real repair
```
