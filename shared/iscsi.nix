# iSCSI and NFS storage configuration for Kubernetes
{ config, pkgs, ... }:

{
  # open-iscsi 2.1.12 dropped node.session.conn_reopen_log_freq from its idbm
  # tables, so iscsiadm refuses to parse node records that 2.1.11 wrote
  # ("Unknown parameter name"), and every Longhorn engine login fails after
  # the upgrade (2026-09-02). Upstream restored it a month after the release
  # (open-iscsi#542); carry that until nixpkgs ships a tag containing it.
  nixpkgs.overlays = [
    (final: prev: {
      openiscsi = prev.openiscsi.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [
          (prev.fetchpatch {
            name = "open-iscsi-542-reopen-log-freq.patch";
            url = "https://github.com/open-iscsi/open-iscsi/commit/8112cdd9514df076dc64ca3d4e85283aa701ce7e.patch";
            hash = "sha256-aC22Efw30iLvyYHtA9uWiGjFDRWSvvjM2AaE0kASJR8=";
          })
        ];
      });
    })
  ];

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
