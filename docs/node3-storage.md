# Node3 Storage: mdadm RAID6

## Current Layout

6x WDC WD100EMAZ 10TB drives in RAID6 on `/dev/md0`, mounted at `/mnt/storage`.

| Serial | Device |
|--------|--------|
| 1EG20UXZ | sda |
| JEKY7J2Z | sdb |
| JEKY6SMZ | sdc |
| 1EG1MM9Z | sdd |
| 1EG11K9Z | sde |
| 1EG191TZ | sdf |

- **Usable capacity:** ~40TB (4 drives worth)
- **Fault tolerance:** any 2 drives can fail
- **Filesystem:** ext4

## Initial Setup

Run once on node3 after partitioning/formatting the individual drives:

```bash
# Create the RAID6 array
mdadm --create /dev/md0 --level=6 --raid-devices=6 \
  /dev/disk/by-id/ata-WDC_WD100EMAZ-00WJTA0_1EG20UXZ-part1 \
  /dev/disk/by-id/ata-WDC_WD100EMAZ-00WJTA0_JEKY7J2Z-part1 \
  /dev/disk/by-id/ata-WDC_WD100EMAZ-00WJTA0_JEKY6SMZ-part1 \
  /dev/disk/by-id/ata-WDC_WD100EMAZ-00WJTA0_1EG1MM9Z-part1 \
  /dev/disk/by-id/ata-WDC_WD100EMAZ-00WJTA0_1EG11K9Z-part1 \
  /dev/disk/by-id/ata-WDC_WD100EMAZ-00WJTA0_1EG191TZ-part1

# Format the array
mkfs.ext4 -m 0 /dev/md0

# Get the UUID and update storage.nix
blkid /dev/md0

# Save mdadm config (NixOS reads this on boot)
mdadm --detail --scan >> /etc/mdadm.conf
```

Initial sync takes several hours for 10TB drives. Monitor with `cat /proc/mdstat`.

## Adding Drives to Expand the Array

mdadm RAID6 can grow by adding drives:

```bash
# Add new drive(s) to the array
mdadm --add /dev/md0 /dev/disk/by-id/ata-NEW_DRIVE-part1

# Grow the array to use the new drive
mdadm --grow /dev/md0 --raid-devices=7

# Reshape takes a long time — monitor with:
cat /proc/mdstat

# After reshape completes, grow the filesystem
resize2fs /dev/md0
```

Update `storage.nix` comments to reflect the new drive count.

### Mixed Drive Sizes

All drives in a RAID6 array use only as much space as the smallest drive. To use a 14TB drive with 10TB drives, partition the 14TB drive with a 10TB partition for the array (the remaining space is unused or can be used separately).

```bash
# Create a 10TB partition on a larger drive
fdisk /dev/disk/by-id/ata-LARGE_DRIVE
# Use +10T for the partition size instead of accepting the default
```

## Replacing a Failed Drive

1. **Identify the failed drive:**

   ```bash
   cat /proc/mdstat
   mdadm --detail /dev/md0
   ```

2. **Mark it as failed (if not already):**

   ```bash
   mdadm /dev/md0 --fail /dev/disk/by-id/ata-FAILED_DRIVE-part1
   mdadm /dev/md0 --remove /dev/disk/by-id/ata-FAILED_DRIVE-part1
   ```

3. **Physically swap** the drive.

4. **Partition the new drive:**

   ```bash
   echo -e "g\nn\n\n\n\nw" | fdisk /dev/disk/by-id/ata-NEW_DRIVE
   ```

5. **Add it to the array:**

   ```bash
   mdadm /dev/md0 --add /dev/disk/by-id/ata-NEW_DRIVE-part1
   ```

   Rebuild starts automatically. Monitor with `cat /proc/mdstat`.

6. **Update `storage.nix`** with the new drive's `by-id` in comments.

## Useful Commands

```bash
# Array status and rebuild progress
cat /proc/mdstat

# Detailed array info
mdadm --detail /dev/md0

# Check filesystem
df -h /mnt/storage

# Run filesystem check (unmount first)
umount /mnt/storage
e2fsck -f /dev/md0
mount /mnt/storage

# SMART check on individual drives
smartctl -a /dev/sda
```
