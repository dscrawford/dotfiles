# kubernetes.nix
{ config, pkgs, lib, hostname, ip, kubeMasterIP, kubeMasterHostName, kubeMasterAPIServerPort, ... }:
let
  isMaster = ip == kubeMasterIP;
in
{
  environment.systemPackages = with pkgs; [
    kompose
    kubectl
    kubernetes
  ];

  services.kubernetes = {
    roles = if isMaster then [ "master" "node" ] else [ "node" ];
    masterAddress = if isMaster then "127.0.0.1" else kubeMasterIP;
    apiserverAddress = "https://${kubeMasterHostname}:${toString kubeMasterAPIServerPort}";
    easyCerts = true;

    apiserver = lib.mkIf isMaster {
      securePort = kubeMasterAPIServerPort;
      advertiseAddress = kubeMasterIP;
      bindAddress = "0.0.0.0";
      etcd = {
        servers = lib.mkForce [ "https://${kubeMasterIP}:2379" ];
      };
      extraOpts = "--allow-privileged=true";
    };

    proxy.enable = true;
    addons.dns.enable = true;
    kubelet = {
      enable = true;
      nodeIp = ip;
      extraOpts = "--anonymous-auth=true";
    };
  };

  systemd.services = lib.mkIf isMaster {
    kube-controller-manager.serviceConfig = {
      Restart = "on-failure";
      StartLimitBurst = 5;
      StartLimitIntervalSec = 10;
    };
    etcd.environment = {
      ETCD_LISTEN_CLIENT_URLS = lib.mkForce "https://127.0.0.1:2379,https://${kubeMasterIP}:2379";
      ETCD_ADVERTISE_CLIENT_URLS = lib.mkForce "https://${kubeMasterIP}:2379,https://etcd.local:2379";
    };
  };
}
