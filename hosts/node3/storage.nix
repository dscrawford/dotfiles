# hosts/node3/storage.nix
# mdadm RAID6 across 6x 10TB SAS drives (~40TB usable) backing Longhorn's
# "media" disk. Array creation and UUID discovery: docs/node3-storage.md.
#
# The SAS drives enumerate ~8s after local-fs.target, udev's incremental
# assembly does not pick them up, and with `nofail` the node used to boot
# without the array while Longhorn quietly adopted the empty mountpoint on the
# root fs as the disk (docs/reboot-resilience-research.md, 2026-09-02). Hence:
# an explicit ARRAY line, the personalities loaded up front, a retrying
# assemble unit the mount depends on, kubelet/containerd refusing to start
# without the mount, and an immutable mountpoint so Longhorn cannot write a
# disk config onto the root fs.
{ pkgs, lib, ... }:

let
  arrayUUID = "fe7545fb:b91b0af5:912acc2a:4e6cc046";
  mountPoint = "/mnt/storage";
in
{
  boot = {
    swraid = {
      enable = true;
      mdadmConf = ''
        MAILADDR root
        DEVICE partitions
        ARRAY /dev/md0 metadata=1.2 UUID=${arrayUUID}
      '';
    };
    initrd.availableKernelModules = [ "mpt3sas" ];
    kernelModules = [ "md_mod" "raid456" ];
  };

  systemd.services.mdadm-assemble-storage = {
    description = "Assemble /dev/md0 for ${mountPoint}";
    wantedBy = [ "multi-user.target" ];
    before = [ "mnt-storage.mount" ];
    after = [ "systemd-udev-settle.service" ];
    unitConfig.DefaultDependencies = false;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [ pkgs.mdadm pkgs.coreutils ];
    script = ''
      for _ in $(seq 1 60); do
        if mdadm --detail /dev/md0 >/dev/null 2>&1; then exit 0; fi
        mdadm --assemble --scan --uuid=${arrayUUID} && exit 0
        sleep 2
      done
      echo "mdadm-assemble-storage: array ${arrayUUID} did not assemble" >&2
      exit 1
    '';
  };

  fileSystems.${mountPoint} = {
    device = "/dev/disk/by-uuid/abef8108-3220-4ba6-9d75-753671a4a021";
    fsType = "ext4";
    # nofail keeps the node bootable and reachable without the array; the
    # hard requirement lives on kubelet/containerd below instead.
    options = [
      "defaults"
      "noatime"
      "nofail"
      "x-systemd.requires=mdadm-assemble-storage.service"
      "x-systemd.device-timeout=120s"
    ];
  };

  systemd.services.containerd.unitConfig.RequiresMountsFor = [ mountPoint ];
  systemd.services.kubelet.unitConfig = {
    RequiresMountsFor = [ mountPoint ];
    # Assert, not Condition: a failed Condition is skipped silently and never
    # retried, which would leave the node quietly out of the cluster.
    AssertPathIsMountPoint = mountPoint;
  };

  # Longhorn regenerates longhorn-disk.cfg on an empty directory that matches
  # its recorded disk UUID, so deleting the stray cfg is not a safeguard;
  # making the directory immutable makes that generation fail and the disk
  # NotReady instead.
  system.activationScripts.storageMountpointImmutable = lib.stringAfter [ "specialfs" ] ''
    mkdir -p ${mountPoint}
    if ! ${pkgs.util-linux}/bin/mountpoint -q ${mountPoint}; then
      ${pkgs.e2fsprogs}/bin/chattr +i ${mountPoint} || true
    fi
  '';
}
