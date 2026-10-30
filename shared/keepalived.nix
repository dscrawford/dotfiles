{ config, pkgs, lib, hostname, ip, netInterface ? "eno1", kubeApiVIP, kubeNodes, kubeMasterAPIServerPort, ... }:
let
  rank = lib.lists.findFirstIndex (n: n == hostname) 0 (lib.attrNames kubeNodes);
  peers = lib.attrValues (lib.removeAttrs kubeNodes [ hostname ]);
  podCidr = config.services.kubernetes.clusterCidr;
in
{
  # VRRP has no authentication: a forged advert from any host or pod would
  # take the VIP down, so only the peers' unicast adverts are let in.
  networking.firewall = {
    extraCommands = lib.concatMapStrings (a: ''
      iptables -A nixos-fw -p vrrp -s ${a} -j nixos-fw-accept
    '') peers + ''
      iptables -t raw -D PREROUTING -s ${podCidr} -p vrrp -j DROP 2>/dev/null || true
      iptables -t raw -I PREROUTING -s ${podCidr} -p vrrp -j DROP
    '';
    extraStopCommands = ''
      iptables -t raw -D PREROUTING -s ${podCidr} -p vrrp -j DROP 2>/dev/null || true
    '';
  };

  users.users.keepalived_script = { isSystemUser = true; group = "keepalived_script"; };
  users.groups.keepalived_script = { };

  services.keepalived = {
    enable = true;
    enableScriptSecurity = true;
    vrrpScripts.chk_apiserver = {
      script = "${pkgs.curl}/bin/curl -sfk --max-time 2 https://127.0.0.1:${toString kubeMasterAPIServerPort}/healthz";
      interval = 2;
      rise = 2;
      weight = -50;
    };
    vrrpInstances.kube-api = {
      interface = netInterface;
      virtualRouterId = 51;
      priority = 110 - rank;
      noPreempt = true;
      unicastSrcIp = ip;
      unicastPeers = peers;
      virtualIps = [ { addr = "${kubeApiVIP}/24"; } ];
      trackScripts = [ "chk_apiserver" ];
      extraConfig = "check_unicast_src";
    };
  };
}
