# hosts/node3/storage.nix
# mdadm RAID6 storage array for Longhorn compatibility
# Layout: 6x 10TB drives in RAID6 = ~40TB usable, 2-disk fault tolerance
#
# Drives:
#   1EG20UXZ (sda), JEKY7J2Z (sdb), JEKY6SMZ (sdc),
#   1EG1MM9Z (sdd), 1EG11K9Z (sde), 1EG191TZ (sdf)
#
# Initial setup (run once on node3):
#
#   mdadm --create /dev/md0 --level=6 --raid-devices=6 \
#     /dev/disk/by-id/ata-WDC_WD100EMAZ-00WJTA0_1EG20UXZ-part1 \
#     /dev/disk/by-id/ata-WDC_WD100EMAZ-00WJTA0_JEKY7J2Z-part1 \
#     /dev/disk/by-id/ata-WDC_WD100EMAZ-00WJTA0_JEKY6SMZ-part1 \
#     /dev/disk/by-id/ata-WDC_WD100EMAZ-00WJTA0_1EG1MM9Z-part1 \
#     /dev/disk/by-id/ata-WDC_WD100EMAZ-00WJTA0_1EG11K9Z-part1 \
#     /dev/disk/by-id/ata-WDC_WD100EMAZ-00WJTA0_1EG191TZ-part1
#
#   mkfs.ext4 -m 0 /dev/md0
#
# After formatting, get the UUID:
#   blkid /dev/md0
# Then update the fileSystems entry below with the actual UUID.
{ ... }:

{
  # Enable mdadm RAID support
  boot.swraid = {
    enable = true;
    mdadmConf = ''
      MAILADDR root
    '';
  };

  # RAID6 array mounted for Longhorn storage
  fileSystems."/mnt/storage" = {
    device = "/dev/disk/by-uuid/abef8108-3220-4ba6-9d75-753671a4a021";
    fsType = "ext4";
    options = [ "defaults" "noatime" "nofail" ];
  };
}
