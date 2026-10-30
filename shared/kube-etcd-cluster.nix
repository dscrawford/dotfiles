{ config, pkgs, lib, hostname, ip, kubeNodes, ... }:
let
  secrets = config.services.kubernetes.secretsPath;
  peerUrl = a: "https://${a}:2380";
  clientUrl = a: "https://${a}:2379";
  selfPeerUrl = peerUrl ip;
  localClientUrl = "https://127.0.0.1:2379";
  peerIPs = lib.attrValues (lib.removeAttrs kubeNodes [ hostname ]);
  podCidr = config.services.kubernetes.clusterCidr;
  joinEnv = "/run/etcd/join.env";
  etcdctl = "etcdctl --cacert=${secrets}/ca.pem --cert=${secrets}/etcd.pem --key=${secrets}/etcd-key.pem --command-timeout=10s";
  localEtcdctl = "${etcdctl} --endpoints=${localClientUrl}";

  # Table rows are | ID | STATUS | NAME | PEER ADDRS | CLIENT ADDRS | IS LEARNER |;
  # unlike -w simple, a "u1,u2" peer cell stays unambiguous. Emitted tab-separated
  # as id, status, name, peers, learner.
  memberRows = ''awk -F' *[|] *' '$2 ~ /^[0-9a-f]+$/ { print $2 "\t" $3 "\t" $4 "\t" $5 "\t" $7 }' '';
  nameByUrl = lib.concatStringsSep "; " (lib.mapAttrsToList (n: a: ''name["${peerUrl a}"] = "${n}"'') kubeNodes);
in
{
  services.etcd = {
    name = hostname;
    listenClientUrls = lib.mkForce [ localClientUrl (clientUrl ip) ];
    listenPeerUrls = lib.mkForce [ selfPeerUrl ];
    advertiseClientUrls = lib.mkForce [ (clientUrl ip) ];
    initialAdvertisePeerUrls = lib.mkForce [ selfPeerUrl ];
    initialCluster = lib.mkForce (lib.mapAttrsToList (n: a: "${n}=${peerUrl a}") kubeNodes);
    initialClusterState = "existing";
  };

  # Any cert the cluster CA signed is etcd root, so only the peers may reach
  # 2379/2380; pods are dropped before routing so neither the local bridge nor
  # flannel's masquerade lets them through.
  networking.firewall = {
    extraCommands = lib.concatMapStrings (a: ''
      iptables -A nixos-fw -p tcp -s ${a} -m multiport --dports 2379,2380 -j nixos-fw-accept
    '') peerIPs + ''
      iptables -t raw -D PREROUTING -s ${podCidr} -p tcp -m multiport --dports 2379,2380 -j DROP 2>/dev/null || true
      iptables -t raw -I PREROUTING -s ${podCidr} -p tcp -m multiport --dports 2379,2380 -j DROP
    '';
    extraStopCommands = ''
      iptables -t raw -D PREROUTING -s ${podCidr} -p tcp -m multiport --dports 2379,2380 -j DROP 2>/dev/null || true
    '';
  };

  systemd.services.etcd = {
    path = [ pkgs.etcd pkgs.gawk ];
    serviceConfig = {
      RuntimeDirectory = "etcd";
      EnvironmentFile = "-${joinEnv}";
      TimeoutStartSec = "20min";
    };

    preStart = ''
      set -o pipefail
      rm -f ${joinEnv}
      for _ in $(seq 1 60); do
        [ -s ${secrets}/etcd.pem ] && [ -s ${secrets}/etcd-key.pem ] && break
        sleep 2
      done
      [ -s ${secrets}/etcd.pem ] && [ -s ${secrets}/etcd-key.pem ] || { echo "etcd-join: certmgr has not issued etcd.pem" >&2; exit 1; }
      [ -d "$ETCD_DATA_DIR/member" ] && exit 0

      members=""
      for peer in ${lib.concatStringsSep " " peerIPs}; do
        endpoint=https://$peer:2379
        if members=$(${etcdctl} --endpoints=$endpoint member list -w table 2>/dev/null | ${memberRows}) && [ -n "$members" ]; then
          break
        fi
        members=""
      done
      if [ -z "$members" ]; then
        echo "etcd-join: no cluster member reachable; starting with the static initial cluster" >&2
        exit 0
      fi

      stale=$(printf '%s\n' "$members" | awk -F'\t' -v me=${hostname} -v url=${selfPeerUrl} \
        '$3 == me || index("," $4 ",", "," url ",") { print $1 }')
      if [ -n "$stale" ]; then
        echo "etcd-join: data dir is empty but member $stale is registered; replacing it"
        ${etcdctl} --endpoints=$endpoint member remove "$stale" >/dev/null
      fi
      ${etcdctl} --endpoints=$endpoint member add ${hostname} --learner --peer-urls=${selfPeerUrl} >/dev/null
      members=$(${etcdctl} --endpoints=$endpoint member list -w table | ${memberRows})

      initial=$(printf '%s\n' "$members" | awk -F'\t' '
        BEGIN { ${nameByUrl} }
        { n = split($4, urls, ",")
          for (i = 1; i <= n; i++) {
            label = ($3 != "") ? $3 : name[urls[i]]
            if (label == "") { print "etcd-join: cannot name member " $1 " at " urls[i] > "/dev/stderr"; exit 1 }
            out = out (out ? "," : "") label "=" urls[i]
          } }
        END { print out }')
      printf 'ETCD_INITIAL_CLUSTER=%s\nETCD_INITIAL_CLUSTER_STATE=existing\n' "$initial" > ${joinEnv}
      echo "etcd-join: joining as learner with $initial"
    '';

    postStart = ''
      set -o pipefail
      self_row() {
        ${localEtcdctl} member list -w table 2>/dev/null | ${memberRows} \
          | awk -F'\t' -v me=${hostname} 'NR == 1 { first = $0 } $3 == me { print; found = 1 } END { if (!found && NR == 1) print first }'
      }
      self=""
      for _ in $(seq 1 60); do
        self=$(self_row)
        [ -n "$self" ] && break
        sleep 2
      done
      [ -n "$self" ] || { echo "etcd-join: cannot find this member" >&2; exit 1; }
      IFS=$'\t' read -r id _ _ peers learner <<<"$self"

      if [ "$peers" != "${selfPeerUrl}" ]; then
        echo "etcd-join: updating peer URL $peers -> ${selfPeerUrl}"
        ${localEtcdctl} member update "$id" --peer-urls=${selfPeerUrl}
      fi

      [ "$learner" = true ] || exit 0
      for _ in $(seq 1 180); do
        if ${localEtcdctl} member promote "$id" 2>/dev/null; then
          echo "etcd-join: promoted to voting member"
          exit 0
        fi
        IFS=$'\t' read -r _ _ _ _ learner <<<"$(self_row)"
        [ "$learner" = true ] || exit 0
        sleep 5
      done
      echo "etcd-join: learner did not catch up in 15 minutes" >&2
      exit 1
    '';
  };
}
