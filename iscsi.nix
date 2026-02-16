# iSCSI and NFS storage configuration for Kubernetes
{ config, pkgs, ... }:

{
  # === Boot ===
  boot = {
    kernelModules = [ "iscsi_tcp" ];
    supportedFilesystems = [ "nfs" "nfs4" ];
  };

  # === Services ===
  services = {
    # iSCSI initiator configuration
    openiscsi = {
      enable = true;
      name = "iqn.2026-01.com.dcraw:${config.networking.hostName}";
    };

    # NFS support for Kubernetes storage
    rpcbind.enable = true;
    nfs.server.enable = false;
  };

  # === Systemd ===
  systemd.services.iscsid = {
    wantedBy = [ "multi-user.target" ];
    before = [ "kubelet.service" ];
  };

  # === Environment ===
  environment.systemPackages = with pkgs; [
    nfs-utils
    util-linux
    openiscsi
  ];

  # === System Activation ===
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
