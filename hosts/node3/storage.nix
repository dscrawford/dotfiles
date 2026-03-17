# hosts/node3/storage.nix
# mergerfs + SnapRAID storage array
# Layout: 4 data drives + 2 parity drives = ~40TB usable, 2-disk fault tolerance
#
# Parity:  1EG20UXZ (sda) → /mnt/parity1,  JEKY7J2Z (sdb) → /mnt/parity2
# Data:    JEKY6SMZ (sdc) → /mnt/disk1,     1EG1MM9Z (sdd) → /mnt/disk2
#          1EG11K9Z (sde) → /mnt/disk3,     1EG191TZ (sdf) → /mnt/disk4
# Pool:    /mnt/storage (mergerfs union of data drives)
#
# Initial setup (run once on node3):
#   wipefs -a /dev/disk/by-id/ata-WDC_WD100EMAZ-00WJTA0_{1EG20UXZ,JEKY7J2Z,JEKY6SMZ,1EG1MM9Z,1EG11K9Z,1EG191TZ}-part1
#   for d in 1EG20UXZ JEKY7J2Z JEKY6SMZ 1EG1MM9Z 1EG11K9Z 1EG191TZ; do
#     mkfs.ext4 -m 0 -T largefile4 /dev/disk/by-id/ata-WDC_WD100EMAZ-00WJTA0_${d}-part1
#   done
#
# After first boot with this config:
#   snapraid sync
{ pkgs, ... }:

{
  environment.systemPackages = [ pkgs.mergerfs ];

  # Data drives
  fileSystems."/mnt/disk1" = {
    device = "/dev/disk/by-id/ata-WDC_WD100EMAZ-00WJTA0_JEKY6SMZ-part1";
    fsType = "ext4";
    options = [ "defaults" "noatime" "nofail" ];
  };
  fileSystems."/mnt/disk2" = {
    device = "/dev/disk/by-id/ata-WDC_WD100EMAZ-00WJTA0_1EG1MM9Z-part1";
    fsType = "ext4";
    options = [ "defaults" "noatime" "nofail" ];
  };
  fileSystems."/mnt/disk3" = {
    device = "/dev/disk/by-id/ata-WDC_WD100EMAZ-00WJTA0_1EG11K9Z-part1";
    fsType = "ext4";
    options = [ "defaults" "noatime" "nofail" ];
  };
  fileSystems."/mnt/disk4" = {
    device = "/dev/disk/by-id/ata-WDC_WD100EMAZ-00WJTA0_1EG191TZ-part1";
    fsType = "ext4";
    options = [ "defaults" "noatime" "nofail" ];
  };

  # Parity drives
  fileSystems."/mnt/parity1" = {
    device = "/dev/disk/by-id/ata-WDC_WD100EMAZ-00WJTA0_1EG20UXZ-part1";
    fsType = "ext4";
    options = [ "defaults" "noatime" "nofail" ];
  };
  fileSystems."/mnt/parity2" = {
    device = "/dev/disk/by-id/ata-WDC_WD100EMAZ-00WJTA0_JEKY7J2Z-part1";
    fsType = "ext4";
    options = [ "defaults" "noatime" "nofail" ];
  };

  # mergerfs — union of data drives into /mnt/storage
  fileSystems."/mnt/storage" = {
    device = "/mnt/disk1:/mnt/disk2:/mnt/disk3:/mnt/disk4";
    fsType = "fuse.mergerfs";
    options = [
      "defaults"
      "noatime"
      "allow_other"
      "use_ino"
      "cache.files=partial"
      "dropcacheonclose=true"
      "moveonenospc=true"
      "category.create=mfs"   # most-free-space: balances writes across drives
      "minfreespace=20G"
      "fsname=mergerfs"
      "nofail"
    ];
    depends = [ "/mnt/disk1" "/mnt/disk2" "/mnt/disk3" "/mnt/disk4" ];
  };

  # SnapRAID — parity protection (sync daily at 3am, scrub weekly)
  services.snapraid = {
    enable = true;
    dataDisks = {
      d1 = "/mnt/disk1/";
      d2 = "/mnt/disk2/";
      d3 = "/mnt/disk3/";
      d4 = "/mnt/disk4/";
    };
    parityFiles = [
      "/mnt/parity1/snapraid.parity"
      "/mnt/parity2/snapraid.2-parity"
    ];
    contentFiles = [
      "/var/lib/snapraid/snapraid.content"
      "/mnt/disk1/snapraid.content"
      "/mnt/disk2/snapraid.content"
    ];
    exclude = [
      "*.unrecoverable"
      "/tmp/"
      "/lost+found/"
      "/snapraid.content"
    ];
    sync.interval = "03:00";
    scrub = {
      interval = "Mon *-*-* 04:00:00";
      plan = 8;
      olderThan = 10;
    };
  };

  # Ensure snapraid content directory exists
  systemd.tmpfiles.rules = [
    "d /var/lib/snapraid 0755 root root -"
  ];
}
