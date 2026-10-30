# iSCSI and NFS storage configuration for Kubernetes
{ config, pkgs, ... }:

{
  boot = {
    kernelModules = [ "iscsi_tcp" ];
    supportedFilesystems = [ "nfs" "nfs4" ];
  };

  services = {
    openiscsi = {
      enable = true;
      name = "iqn.2026-01.com.dcraw:${config.networking.hostName}";
    };

    rpcbind.enable = true;
    nfs.server.enable = false;
  };

  systemd.services.iscsid = {
    wantedBy = [ "multi-user.target" ];
    before = [ "kubelet.service" ];
    # Only Longhorn uses this initiator, and it recreates its node records on
    # every attach; clearing them at boot means a record written by one
    # open-iscsi version can never wedge the next.
    preStart = ''
      rm -rf /etc/iscsi/nodes/* /etc/iscsi/send_targets/*
    '';
  };

  environment.systemPackages = with pkgs; [
    nfs-utils
    util-linux
    openiscsi
  ];

  system.activationScripts.longhorn-compat = let
    iscsi = pkgs.openiscsi;
    nfs = pkgs.nfs-utils;
  in ''
    mkdir -p /usr/sbin /usr/bin
    ln -sf ${iscsi}/bin/iscsiadm /usr/sbin/iscsiadm
    ln -sf ${nfs}/bin/mount.nfs /usr/sbin/mount.nfs
    ln -sf ${nfs}/bin/mount.nfs4 /usr/sbin/mount.nfs4
  '';
}
