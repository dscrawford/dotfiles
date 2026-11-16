# Kubernetes Secrets whose values live sops-encrypted in secrets/kube.yaml, applied
# by the master so KubeServer manifests can reference them without committing them.
# Master-only: kube.yaml is encrypted to node1 (and the admin key) alone.
{ config, pkgs, lib, ... }:

let
  isMaster = config.services.kubernetes.apiserver.enable;
  kubeconfig = "/etc/kubernetes/cluster-admin.kubeconfig";

  # <namespace>/<name> -> { <Secret data key> = "<key in secrets/kube.yaml>"; }
  kubeSecrets = {
    "scooter/imagegen-gemini".GEMINI_API_KEY = "gemini-api-key";
  };

  sopsKeys = lib.unique (lib.concatMap lib.attrValues (lib.attrValues kubeSecrets));

  applyOne = ref: keys:
    let
      parts = lib.splitString "/" ref;
      ns = builtins.elemAt parts 0;
      name = builtins.elemAt parts 1;
      fromFiles = lib.concatStringsSep " " (lib.mapAttrsToList
        (key: sopsKey: "--from-file=${key}=${config.sops.secrets."kube/${sopsKey}".path}") keys);
    in ''
      kubectl create secret generic ${name} -n ${ns} ${fromFiles} --dry-run=client -o yaml \
        | kubectl apply --server-side --force-conflicts --field-manager=dotfiles-kube-secrets -f -
      echo "kube-secrets: applied ${ref}"
    '';

  applyScript = pkgs.writeShellApplication {
    name = "kube-secrets-apply";
    runtimeInputs = [ pkgs.kubectl pkgs.coreutils ];
    text = ''
      export KUBECONFIG="''${KUBECONFIG:-${kubeconfig}}"
      deadline=$(( $(date +%s) + 600 ))
      until kubectl --request-timeout=10s get --raw /readyz >/dev/null 2>&1; do
        if [ "$(date +%s)" -ge "$deadline" ]; then
          echo "kube-secrets: API server not ready after 600s" >&2
          exit 1
        fi
        sleep 5
      done
      ${lib.concatStrings (lib.mapAttrsToList applyOne kubeSecrets)}
    '';
  };
in
lib.mkIf isMaster {
  services.kubernetes.pki.etcClusterAdminKubeconfig = "kubernetes/cluster-admin.kubeconfig";

  sops.secrets = lib.genAttrs (map (k: "kube/${k}") sopsKeys) (path: {
    sopsFile = ../secrets/kube.yaml;
    key = lib.removePrefix "kube/" path;
    restartUnits = [ "kube-secrets.service" ];
  });

  systemd.services.kube-secrets = {
    description = "Apply sops-managed Kubernetes Secrets";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" "kube-apiserver.service" ];
    wants = [ "network-online.target" ];
    # A new secret in kubeSecrets changes the script, so a deploy re-applies.
    restartTriggers = [ applyScript ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${applyScript}/bin/kube-secrets-apply";
    };
  };
}
