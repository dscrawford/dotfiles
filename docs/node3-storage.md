# Node3 Storage: mergerfs + SnapRAID

## Current Layout

| Role | Serial | Mount | Size |
|------|--------|-------|------|
| Parity 1 | 1EG20UXZ | /mnt/parity1 | 10TB |
| Parity 2 | JEKY7J2Z | /mnt/parity2 | 10TB |
| Data 1 | JEKY6SMZ | /mnt/disk1 | 10TB |
| Data 2 | 1EG1MM9Z | /mnt/disk2 | 10TB |
| Data 3 | 1EG11K9Z | /mnt/disk3 | 10TB |
| Data 4 | 1EG191TZ | /mnt/disk4 | 10TB |

- **Pool mount:** `/mnt/storage` (mergerfs union of all data drives)
- **Usable capacity:** ~40TB (4 data drives)
- **Fault tolerance:** 2 drives (any 2 can fail)
- **Parity sync:** daily at 3:00 AM
- **Scrub:** weekly on Mondays at 4:00 AM

## Key Rule

Each parity drive must be **>=** the largest data drive. If you add a 14TB data drive, upgrade parity drives to 14TB+ first.

## Adding a Data Drive

1. **Physically install** the drive and get its ID:

   ```bash
   ls -la /dev/disk/by-id/ | grep -E 'ata-' | grep -v wwn | grep part
   ```

2. **Partition and format:**

   ```bash
   DEV="/dev/disk/by-id/ata-YOUR_DRIVE_ID"
   wipefs -a "$DEV"
   echo -e "g\nn\n\n\n\nw" | fdisk "$DEV"
   mkfs.ext4 -m 0 -T largefile4 "${DEV}-part1"
   ```

3. **Edit `hosts/node3/storage.nix`** — add three things:

   ```nix
   # New filesystem mount
   fileSystems."/mnt/disk5" = {
     device = "/dev/disk/by-id/ata-YOUR_DRIVE_ID-part1";
     fsType = "ext4";
     options = [ "defaults" "noatime" "nofail" ];
   };
   ```

   Add `/mnt/disk5` to the mergerfs device string:
   ```nix
   fileSystems."/mnt/storage" = {
     device = "/mnt/disk1:/mnt/disk2:/mnt/disk3:/mnt/disk4:/mnt/disk5";
     # ...
     depends = [ "/mnt/disk1" "/mnt/disk2" "/mnt/disk3" "/mnt/disk4" "/mnt/disk5" ];
   };
   ```

   Add to snapraid dataDisks:
   ```nix
   services.snapraid.dataDisks = {
     # ... existing entries ...
     d5 = "/mnt/disk5/";
   };
   ```

   Optionally add a content file on the new disk:
   ```nix
   contentFiles = [
     "/var/lib/snapraid/snapraid.content"
     "/mnt/disk1/snapraid.content"
     "/mnt/disk2/snapraid.content"
     "/mnt/disk5/snapraid.content"  # new
   ];
   ```

4. **Deploy and sync:**

   ```bash
   git add -A && sudo nixos-rebuild switch --flake .#node3
   snapraid sync
   ```

## Adding a Parity Drive (3-disk fault tolerance)

1. Partition and format (same as above).

2. **Edit `hosts/node3/storage.nix`:**

   ```nix
   fileSystems."/mnt/parity3" = {
     device = "/dev/disk/by-id/ata-YOUR_DRIVE_ID-part1";
     fsType = "ext4";
     options = [ "defaults" "noatime" "nofail" ];
   };
   ```

   Add to parityFiles:
   ```nix
   parityFiles = [
     "/mnt/parity1/snapraid.parity"
     "/mnt/parity2/snapraid.2-parity"
     "/mnt/parity3/snapraid.3-parity"  # new
   ];
   ```

3. **Deploy and sync:**

   ```bash
   git add -A && sudo nixos-rebuild switch --flake .#node3
   snapraid sync
   ```

## Replacing a Failed Data Drive

1. **Ensure parity is current** (skip if drive is dead):

   ```bash
   snapraid sync
   ```

2. **Identify the failed drive** and its mount (e.g., `/mnt/disk2` = serial `1EG1MM9Z`).

3. **Physically swap** the drive.

4. **Partition and format** the new drive (see "Adding a Data Drive" step 2).

5. **Update `storage.nix`** with the new drive's `by-id`.

6. **Deploy and recover:**

   ```bash
   git add -A && sudo nixos-rebuild switch --flake .#node3
   snapraid fix -d d2          # recovers data for disk d2
   snapraid sync               # updates parity with recovered data
   ```

## Replacing a Parity Drive

1. **Swap** the physical drive.
2. **Partition and format** the new drive.
3. **Update `storage.nix`** with the new `by-id`.
4. **Deploy and rebuild parity:**

   ```bash
   git add -A && sudo nixos-rebuild switch --flake .#node3
   snapraid sync
   ```

## Upgrading a Parity Drive to a Larger Size

Required before adding data drives larger than current parity.

1. `snapraid sync` (ensure current).
2. Swap, partition, format the larger drive.
3. Update `by-id` in `storage.nix`, rebuild.
4. `snapraid sync` (rebuilds parity on larger drive).

Repeat for each parity drive.

## Upgrading a Data Drive to a Larger Size

1. `snapraid sync`
2. Mount the new drive temporarily and copy data from the old drive:

   ```bash
   mkdir /mnt/tmp && mount /dev/disk/by-id/ata-NEW_DRIVE-part1 /mnt/tmp
   rsync -avP /mnt/disk2/ /mnt/tmp/
   ```

3. Swap the old drive out, update `by-id` in `storage.nix`, rebuild.
4. `snapraid sync`

## Useful Commands

```bash
# Check array status
snapraid status

# Manually sync parity (runs automatically daily)
snapraid sync

# Scrub for silent data corruption
snapraid scrub

# Check differences since last sync
snapraid diff

# List all drives and usage
df -h /mnt/disk* /mnt/parity* /mnt/storage

# Check mergerfs pool
cat /etc/mtab | grep mergerfs
```
