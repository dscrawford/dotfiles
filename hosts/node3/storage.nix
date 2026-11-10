# hosts/node3/storage.nix
# mdadm RAID6 arrays backing Longhorn disks. Array creation, UUID discovery
# and the md0 -> md1 migration: docs/node3-storage.md. md1 is xfs because
# ext4's 16 TiB file limit caps a Longhorn replica, hence a volume.
#
# The SAS drives enumerate ~8s after local-fs.target, udev's incremental
# assembly does not pick them up, and with `nofail` the node used to boot
# without the array while Longhorn quietly adopted the empty mountpoint on the
# root fs as the disk (docs/reboot-resilience-research.md, 2026-09-02). Hence:
# an explicit ARRAY line, the personalities loaded up front, a retrying
# assemble unit the mount depends on, kubelet/containerd refusing to start
# without the mounts, and immutable mountpoints so Longhorn cannot write a
# disk config onto the root fs.
{ pkgs, lib, ... }:

let
  arrays = {
    storage = {
      device = "/dev/md0";
      arrayUUID = "fe7545fb:b91b0af5:912acc2a:4e6cc046";
      mountPoint = "/mnt/storage";
      fsUUID = "abef8108-3220-4ba6-9d75-753671a4a021";
      fsType = "ext4";
    };
    data = {
      device = "/dev/md1";
      arrayUUID = "5867dae4:814c13ca:74515fd7:5cf25f31";
      mountPoint = "/mnt/data";
      fsUUID = "6a2d6a11-9f14-4161-846c-ea2c7691c9cc";
      fsType = "xfs";
    };
  };
  mountPoints = lib.mapAttrsToList (_: a: a.mountPoint) arrays;
  mountUnit = mountPoint: "${lib.removePrefix "-" (builtins.replaceStrings [ "/" ] [ "-" ] mountPoint)}.mount";
in
{
  boot = {
    swraid = {
      enable = true;
      mdadmConf = ''
        MAILADDR root
        DEVICE partitions
      '' + lib.concatStrings (lib.mapAttrsToList (_: a: ''
        ARRAY ${a.device} metadata=1.2 UUID=${a.arrayUUID}
      '') arrays);
    };
    initrd.availableKernelModules = [ "mpt3sas" ];
    kernelModules = [ "md_mod" "raid456" ];
  };

  systemd.services = lib.mapAttrs' (name: a: lib.nameValuePair "mdadm-assemble-${name}" {
    description = "Assemble ${a.device} for ${a.mountPoint}";
    wantedBy = [ "multi-user.target" ];
    before = [ (mountUnit a.mountPoint) ];
    after = [ "systemd-udev-settle.service" ];
    unitConfig.DefaultDependencies = false;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [ pkgs.mdadm pkgs.coreutils ];
    script = ''
      for _ in $(seq 1 60); do
        if mdadm --detail ${a.device} >/dev/null 2>&1; then exit 0; fi
        mdadm --assemble --scan --uuid=${a.arrayUUID} && exit 0
        sleep 2
      done
      echo "mdadm-assemble-${name}: array ${a.arrayUUID} did not assemble" >&2
      exit 1
    '';
  }) arrays // {
    containerd.unitConfig.RequiresMountsFor = mountPoints;
    kubelet.unitConfig = {
      RequiresMountsFor = mountPoints;
      # Assert, not Condition: a failed Condition is skipped silently and never
      # retried, which would leave the node quietly out of the cluster.
      AssertPathIsMountPoint = mountPoints;
    };
  };

  fileSystems = lib.mapAttrs' (name: a: lib.nameValuePair a.mountPoint {
    device = "/dev/disk/by-uuid/${a.fsUUID}";
    inherit (a) fsType;
    # nofail keeps the node bootable and reachable without the array; the
    # hard requirement lives on kubelet/containerd above instead.
    options = [
      "defaults"
      "noatime"
      "nofail"
      "x-systemd.requires=mdadm-assemble-${name}.service"
      "x-systemd.device-timeout=120s"
    ];
  }) arrays;

  # Longhorn regenerates longhorn-disk.cfg on an empty directory that matches
  # its recorded disk UUID, so deleting the stray cfg is not a safeguard;
  # making the directory immutable makes that generation fail and the disk
  # NotReady instead.
  system.activationScripts.storageMountpointImmutable = lib.stringAfter [ "specialfs" ] (
    lib.concatMapStrings (mountPoint: ''
      mkdir -p ${mountPoint}
      if ! ${pkgs.util-linux}/bin/mountpoint -q ${mountPoint}; then
        ${pkgs.e2fsprogs}/bin/chattr +i ${mountPoint} || true
      fi
    '') mountPoints
  );
}
