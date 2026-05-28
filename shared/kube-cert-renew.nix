# Safety net for easyCerts: certmgr can silently fail to renew.
# Monthly timer checks all certs, deletes expiring ones, and lets certmgr re-issue.
{ config, pkgs, lib, ... }:

let
  secretsPath = config.services.kubernetes.secretsPath;
  isMaster = config.services.kubernetes.apiserver.enable;

  kubeMasterIP = "192.168.0.2";

  renewScript = pkgs.writeShellApplication {
    name = "kube-cert-renew";
    runtimeInputs = [ pkgs.openssl pkgs.coreutils pkgs.systemd pkgs.openssh ];
    text = ''
      SECRETS="${secretsPath}"
      RENEW_THRESHOLD=$((7 * 24 * 3600))
      RENEWED=0

      if [ ! -d "$SECRETS" ]; then
        echo "kube-cert-renew: secrets dir $SECRETS not found, skipping"
        exit 0
      fi

    '' + lib.optionalString (!isMaster) ''
      # Sync API token from master
      echo "kube-cert-renew: syncing API token from master"
      TOKEN_FILE="$SECRETS/apitoken.secret"
      if ssh -i /home/host/.ssh/id_ed25519 -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new \
           "host@${kubeMasterIP}" "sudo cat /var/lib/cfssl/apitoken.secret" > "$TOKEN_FILE.tmp" 2>/dev/null; then
        mv "$TOKEN_FILE.tmp" "$TOKEN_FILE"
        chmod 600 "$TOKEN_FILE"
        echo "kube-cert-renew: API token synced"
      else
        rm -f "$TOKEN_FILE.tmp"
        echo "kube-cert-renew: WARNING: could not sync API token from master"
      fi

    '' + ''
      NOW=$(date +%s)

      for cert in "$SECRETS"/*.pem; do
        case "$cert" in
          *-key.pem) continue ;;
        esac

        EXPIRY_LINE=$(openssl x509 -in "$cert" -noout -enddate 2>/dev/null) || continue
        EXPIRY="''${EXPIRY_LINE#notAfter=}"
        EXPIRY_EPOCH=$(date -d "$EXPIRY" +%s 2>/dev/null) || continue
        REMAINING=$((EXPIRY_EPOCH - NOW))

        if [ "$REMAINING" -lt "$RENEW_THRESHOLD" ]; then
          CERT_NAME=$(basename "$cert")
          echo "kube-cert-renew: $CERT_NAME expires in $((REMAINING / 3600))h, removing for re-issue"
          rm -f "$cert" "''${cert%.pem}-key.pem"
          RENEWED=$((RENEWED + 1))
        fi
      done

      if [ "$RENEWED" -gt 0 ]; then
        echo "kube-cert-renew: removed $RENEWED expired/expiring cert(s), restarting certmgr"
        systemctl restart certmgr.service

        # Wait for certmgr to re-issue (up to 90s)
        TIMEOUT=90
        i=0
        while [ $i -lt $TIMEOUT ]; do
          MISSING=0
          for cert in "$SECRETS"/*.pem; do
            case "$cert" in
              *-key.pem) continue ;;
            esac
            [ -f "$cert" ] || MISSING=$((MISSING + 1))
          done
          [ "$MISSING" -eq 0 ] && break
          i=$((i + 1))
          sleep 1
        done

        if [ "$i" -ge "$TIMEOUT" ]; then
          echo "kube-cert-renew: WARNING: timed out waiting for certmgr to re-issue certs"
        fi

        # Update kubeconfig cert copies so kubectl keeps working
        KUBE_CERTS="/home/host/.kube/certs"
        if [ -d "$KUBE_CERTS" ]; then
          echo "kube-cert-renew: updating kubeconfig cert copies in $KUBE_CERTS"
          for f in ca.pem cluster-admin.pem cluster-admin-key.pem; do
            if [ -f "$SECRETS/$f" ]; then
              cp "$SECRETS/$f" "$KUBE_CERTS/$f"
              chown host:users "$KUBE_CERTS/$f"
              chmod 600 "$KUBE_CERTS/$f"
            fi
          done
        fi

        echo "kube-cert-renew: restarting kubernetes services"
        systemctl restart kubelet.service || echo "kube-cert-renew: kubelet restart failed"
        systemctl restart kube-proxy.service || echo "kube-cert-renew: kube-proxy restart failed"
        systemctl restart flannel.service || echo "kube-cert-renew: flannel restart failed"
      else
        echo "kube-cert-renew: all certs valid for >7 days, no action needed"
      fi
    '';
  };
in
{
  systemd.services.kube-cert-renew = {
    description = "Kubernetes certificate renewal safety net";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${renewScript}/bin/kube-cert-renew";
    };
    after = [ "network-online.target" ] ++ lib.optionals isMaster [ "cfssl.target" ];
    wants = [ "network-online.target" ];
  };

  systemd.timers.kube-cert-renew = {
    description = "Monthly Kubernetes certificate renewal check";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "monthly";
      RandomizedDelaySec = "6h";
      Persistent = true;
    };
  };
}
