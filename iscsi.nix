# iscsi.nix
{ config, pkgs, ... }:
{
  services.openiscsi = {
    enable = true;
    name = "iqn.2026-01.com.dcraw:${config.networking.hostName}";
  };

  boot.kernelModules = [ "iscsi_tcp" ];

  # NFS Support for Kubernetes storage
  services.rpcbind.enable = true;

  environment.systemPackages = with pkgs; [
    nfs-utils
    util-linux
    openiscsi
  ];

  services.nfs.server.enable = false;
  boot.supportedFilesystems = [ "nfs" "nfs4" ];

  systemd.services.iscsid = {
    wantedBy = [ "multi-user.target" ];
    before = [ "kubelet.service" ];
  };

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
