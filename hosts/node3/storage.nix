# hosts/node3/storage.nix
# mdadm RAID6 across 6x 10TB drives (~40TB usable) backing Longhorn.
# Array creation and UUID discovery: docs/node3-storage.md.
{ ... }:

{
  boot.swraid = {
    enable = true;
    mdadmConf = ''
      MAILADDR root
    '';
  };

  fileSystems."/mnt/storage" = {
    device = "/dev/disk/by-uuid/abef8108-3220-4ba6-9d75-753671a4a021";
    fsType = "ext4";
    options = [ "defaults" "noatime" "nofail" ];
  };
}
