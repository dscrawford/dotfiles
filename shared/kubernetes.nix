# kubernetes.nix
{ config, pkgs, lib, hostname, ip, kubeMasterIP, kubeMasterHostname, kubeMasterAPIServerPort, ... }:
let
  isMaster = ip == kubeMasterIP;
in
{
  # flannel-io moved the v1.9.1-flannel3 tag on 2026-08-07; the channel pinned
  # here (20260816) predates nixpkgs' hash fix (PR #552589, 2026-08-18). Drop
  # once nixpkgs is bumped past it.
  nixpkgs.overlays = [
    (final: prev: {
      cni-plugin-flannel = prev.cni-plugin-flannel.overrideAttrs (old: {
        src = prev.fetchFromGitHub {
          owner = "flannel-io";
          repo = "cni-plugin";
          rev = "v${old.version}";
          hash = "sha256-lYn9qDmUn8g3nnD4wQqyzKjd/lPXqoER5nZuY0sVK0s=";
        };
      });
    })
  ];

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

    # Upstream default is 720h; renewal runs via certmgr + kube-cert-renew.nix.
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

  # Pod source IPs must survive the hop between nodes or NetworkPolicy (enforced
  # by kube-router, KubeServer config/kube-router/) cannot match them. The flannel
  # CNI plugin defaults the bridge's ipMasq to the inverse of flanneld's, and
  # NixOS runs flanneld without --ip-masq, so by default every pod gets a
  # per-pod MASQUERADE chain that rewrites off-subnet traffic to the node IP.
  # Flip it: flanneld masquerades only traffic leaving 10.1.0.0/16, the bridge
  # masquerades nothing. Pods created before this change keep their old chain
  # until recreated.
  services.kubernetes.kubelet.cni.config = [
    {
      name = "mynet";
      type = "flannel";
      cniVersion = "0.3.1";
      delegate = {
        isDefaultGateway = true;
        hairpinMode = true;
        bridge = "mynet";
        ipMasq = false;
      };
    }
  ];

  # Second CRI runtime, selected per pod via RuntimeClass `crun` (KubeServer
  # config/scooter/runtimeclass.yaml). crun delegates a writable cgroup subtree to
  # the container, which systemd-as-PID-1 images (Scooter sandboxes) need to run
  # unprivileged in their own cgroup namespace; under runc they only boot
  # privileged-equivalent in the host cgroup namespace and churn kubepods.slice.
  virtualisation.containerd.settings.plugins."io.containerd.grpc.v1.cri".containerd.runtimes.crun = {
    runtime_type = "io.containerd.runc.v2";
    options = {
      BinaryName = "${pkgs.crun}/bin/crun";
      SystemdCgroup = true;
    };
  };

  systemd.services = lib.mkMerge [
    { flannel.environment.FLANNELD_IP_MASQ = "true"; }
    (lib.mkIf isMaster {
      kube-controller-manager.serviceConfig = {
        Restart = "on-failure";
        StartLimitBurst = 5;
        StartLimitIntervalSec = 10;
      };
      etcd.environment = {
        ETCD_LISTEN_CLIENT_URLS = lib.mkForce "https://127.0.0.1:2379,https://${kubeMasterIP}:2379";
        ETCD_ADVERTISE_CLIENT_URLS = lib.mkForce "https://${kubeMasterIP}:2379,https://etcd.local:2379";
      };
    })
  ];
}
