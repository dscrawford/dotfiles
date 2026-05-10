# kubernetes.nix
{ config, pkgs, lib, hostname, ip, kubeMasterIP, kubeMasterHostname, kubeMasterAPIServerPort, ... }:
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
    pki.cfsslAPIExtraSANs = lib.mkIf isMaster [ kubeMasterIP ];

    # Override CFSSL cert lifetime from upstream 720h (30 days) to 8760h (1 year).
    # Renewal is handled by certmgr + kube-cert-renew.nix safety-net timer.
  };

  services.cfssl.configFile = lib.mkIf isMaster (lib.mkForce (toString (pkgs.writeText "cfssl-config.json" (builtins.toJSON {
    signing.profiles.default = {
      usages = [ "digital signature" ];
      auth_key = "default";
      expiry = "8760h";  # 1 year
    };
    auth_keys.default = {
      type = "standard";
      key = "file:${config.services.cfssl.dataDir}/apitoken.secret";
    };
  }))));

  services.kubernetes = {
    apiserver = lib.mkIf isMaster {
      securePort = kubeMasterAPIServerPort;
      advertiseAddress = kubeMasterIP;
      bindAddress = "0.0.0.0";
      etcd = {
        servers = lib.mkForce [ "https://${kubeMasterIP}:2379" ];
      };
      extraOpts = "--allow-privileged=true";
      extraSANs = [ kubeMasterHostname ];
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
