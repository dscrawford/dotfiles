#!/usr/bin/env bats

setup_file() {
  cd "$BATS_TEST_DIRNAME/../.."
  export HA_JSON="$BATS_FILE_TMPDIR/ha.json"
  nix eval --json '.?submodules=1#nixosConfigurations' --apply '
    cs:
    let
      node = n: let c = cs.${n}.config; in {
        roles = c.services.kubernetes.roles;
        apiserverAddress = c.services.kubernetes.apiserverAddress;
        masterAddress = c.services.kubernetes.masterAddress;
        extraHosts = c.networking.extraHosts;
        cfssl = c.services.cfssl.enable;
        cfsslUnit = c.systemd.services.cfssl.enable;
        cfsslPreStart = c.systemd.services.cfssl.preStart;
        bootstrapPreStart = c.systemd.services.kube-certmgr-bootstrap.preStart;
        saSigningKey = c.services.kubernetes.apiserver.serviceAccountSigningKeyFile;
        saKey = c.services.kubernetes.apiserver.serviceAccountKeyFile;
        cmSaKey = c.services.kubernetes.controllerManager.serviceAccountKeyFile;
        saOwner = c.sops.secrets.kube_sa_key.owner;
        tokenOwner = c.sops.secrets.kube_apitoken.owner;
        extraOpts = c.services.kubernetes.apiserver.extraOpts;
        extraSANs = c.services.kubernetes.apiserver.extraSANs;
        advertiseAddress = c.services.kubernetes.apiserver.advertiseAddress;
        etcdServers = c.services.kubernetes.apiserver.etcd.servers;
        etcd = { inherit (c.services.etcd) name listenPeerUrls listenClientUrls advertiseClientUrls
                   initialAdvertisePeerUrls initialCluster initialClusterState openFirewall; };
        etcdUnit = { inherit (c.systemd.services.etcd.serviceConfig) EnvironmentFile RuntimeDirectory TimeoutStartSec;
                     listen = c.systemd.services.etcd.environment.ETCD_LISTEN_CLIENT_URLS; };
        vrrp = { inherit (c.services.keepalived.vrrpInstances.kube-api) priority unicastSrcIp unicastPeers
                   interface noPreempt extraConfig;
                 vip = (builtins.head c.services.keepalived.vrrpInstances.kube-api.virtualIps).addr; };
        keepalivedFirewall = c.services.keepalived.openFirewall;
        checkUser = c.services.keepalived.vrrpScripts.chk_apiserver.user;
        tcpPorts = c.networking.firewall.allowedTCPPorts;
        firewallCommands = c.networking.firewall.extraCommands;
      };
    in builtins.listToAttrs (map (n: { name = n; value = node n; }) [ "node1" "node2" "node3" ])
       // { local.vip = cs.local.config.networking.hosts."192.168.0.10"; }
  ' > "$HA_JSON" 2>/dev/null
}

q() {
  python3 -I - "$HA_JSON" "$1" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
for k in sys.argv[2].strip(".").split("."):
    d = d[k]
if isinstance(d, list): print(" ".join(map(str, d)))
elif isinstance(d, bool): print(json.dumps(d))
else: print(d)
EOF
}

nodes="node1 node2 node3"

@test "every node runs master and node roles" {
  for n in $nodes; do [ "$(q $n.roles)" = "master node" ]; done
}

@test "apiserverAddress is the VIP name, masterAddress stays the cfssl host" {
  for n in $nodes; do
    [ "$(q $n.apiserverAddress)" = "https://api.kube:6443" ]
    [ "$(q $n.masterAddress)" = "192.168.0.2" ]
  done
}

@test "api.kube resolves to the VIP on nodes and desktop" {
  hosts="$(q node2.extraHosts)"
  [[ "$hosts" == *"192.168.0.10 api.kube"* ]]
  [[ "$hosts" != *"192.168.0.2 api.kube"* ]]
  [ "$(q local.vip)" = "api.kube" ]
}

@test "cfssl runs on node1 only" {
  [ "$(q node1.cfssl)" = true ]
  [ "$(q node1.cfsslUnit)" = true ]
  for n in node2 node3; do
    [ "$(q $n.cfssl)" = false ]
    [ "$(q $n.cfsslUnit)" = false ]
  done
}

@test "service-account key is the sops secret on every apiserver and controller-manager" {
  for n in $nodes; do
    for k in saSigningKey saKey cmSaKey; do [ "$(q $n.$k)" = "/run/secrets/kube_sa_key" ]; done
    [ "$(q $n.saOwner)" = kubernetes ]
  done
}

@test "node1 also verifies tokens signed by its previous certmgr key" {
  [[ "$(q node1.extraOpts)" == *"--service-account-key-file=/var/lib/kubernetes/secrets/service-account.pem"* ]]
  [[ "$(q node2.extraOpts)" != *"service-account-key-file"* ]]
}

@test "cfssl API token: copied into cfssl's state on node1, symlinked for certmgr elsewhere" {
  [ "$(q node1.tokenOwner)" = cfssl ]
  [[ "$(q node1.cfsslPreStart)" == *"install -m 400 /run/secrets/kube_apitoken /var/lib/cfssl/apitoken.secret"* ]]
  [ "$(q node2.tokenOwner)" = root ]
  [[ "$(q node2.bootstrapPreStart)" == *"ln -sfn /run/secrets/kube_apitoken /var/lib/kubernetes/secrets/apitoken.secret"* ]]
  [ "$(q node1.bootstrapPreStart)" = "" ]
}

@test "apiserver cert carries api.kube, the VIP and every node IP; advertises its own IP" {
  [ "$(q node3.extraSANs)" = "api.kube 192.168.0.10 192.168.0.2 192.168.0.4 192.168.0.6" ]
  [ "$(q node3.advertiseAddress)" = "192.168.0.6" ]
}

@test "apiserver talks to all three etcd members" {
  [ "$(q node1.etcdServers)" = "https://192.168.0.2:2379 https://192.168.0.4:2379 https://192.168.0.6:2379" ]
}

@test "etcd: per-node name and URLs, full initial cluster, joins as existing" {
  while IFS='|' read -r n ip; do
    [ "$(q $n.etcd.name)" = "$n" ]
    [ "$(q $n.etcd.listenPeerUrls)" = "https://$ip:2380" ]
    [ "$(q $n.etcd.listenClientUrls)" = "https://127.0.0.1:2379 https://$ip:2379" ]
    [ "$(q $n.etcdUnit.listen)" = "https://127.0.0.1:2379,https://$ip:2379" ]
    [ "$(q $n.etcd.advertiseClientUrls)" = "https://$ip:2379" ]
    [ "$(q $n.etcd.initialAdvertisePeerUrls)" = "https://$ip:2380" ]
    [ "$(q $n.etcd.initialCluster)" = "node1=https://192.168.0.2:2380 node2=https://192.168.0.4:2380 node3=https://192.168.0.6:2380" ]
    [ "$(q $n.etcd.initialClusterState)" = existing ]
  done <<'EOF'
node1|192.168.0.2
node2|192.168.0.4
node3|192.168.0.6
EOF
}

@test "etcd unit: join env from pre-start, start timeout covers the promote wait" {
  [ "$(q node2.etcdUnit.EnvironmentFile)" = "-/run/etcd/join.env" ]
  [ "$(q node2.etcdUnit.RuntimeDirectory)" = etcd ]
  [ "$(q node2.etcdUnit.TimeoutStartSec)" = 20min ]
}

@test "etcd ports are open to the two peers only and closed to pods" {
  while IFS='|' read -r n peers; do
    [ "$(q $n.etcd.openFirewall)" = false ]
    [[ " $(q $n.tcpPorts) " != *" 2379 "* ]]
    rules="$(q $n.firewallCommands)"
    for p in $peers; do
      [[ "$rules" == *"-p tcp -s $p -m multiport --dports 2379,2380 -j nixos-fw-accept"* ]]
    done
    [[ "$rules" != *"-s $(q $n.vrrp.unicastSrcIp) -m multiport"* ]]
    [[ "$rules" == *"-t raw -I PREROUTING -s 10.1.0.0/16 -p tcp -m multiport --dports 2379,2380 -j DROP"* ]]
  done <<'EOF'
node1|192.168.0.4 192.168.0.6
node2|192.168.0.2 192.168.0.6
node3|192.168.0.2 192.168.0.4
EOF
}

@test "keepalived: distinct priorities, unicast to the other two nodes, VRRP accepted from peers only" {
  while IFS='|' read -r n ip prio peers; do
    [ "$(q $n.vrrp.priority)" = "$prio" ]
    [ "$(q $n.vrrp.unicastSrcIp)" = "$ip" ]
    [ "$(q $n.vrrp.unicastPeers)" = "$peers" ]
    [ "$(q $n.vrrp.vip)" = "192.168.0.10/24" ]
    [ "$(q $n.vrrp.noPreempt)" = true ]
    [[ "$(q $n.vrrp.extraConfig)" == *check_unicast_src* ]]
    [ "$(q $n.keepalivedFirewall)" = false ]
    rules="$(q $n.firewallCommands)"
    for p in $peers; do [[ "$rules" == *"-p vrrp -s $p -j nixos-fw-accept"* ]]; done
    [[ "$rules" == *"-t raw -I PREROUTING -s 10.1.0.0/16 -p vrrp -j DROP"* ]]
  done <<'EOF'
node1|192.168.0.2|110|192.168.0.4 192.168.0.6
node2|192.168.0.4|109|192.168.0.2 192.168.0.6
node3|192.168.0.6|108|192.168.0.2 192.168.0.4
EOF
  [ "$(q node3.vrrp.interface)" = enp5s0 ]
  [ "$(q node1.checkUser)" = keepalived_script ]
}
