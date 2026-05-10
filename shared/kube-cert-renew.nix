# Automatic Kubernetes certificate renewal safety net.
# certmgr (from easyCerts) should handle renewal, but can silently fail.
# This timer runs monthly, checks all certs under /var/lib/kubernetes/secrets,
# deletes any that are expired or within 7 days of expiry, then restarts
# certmgr to re-issue them and bounces the affected kubernetes services.
{ config, pkgs, lib, ... }:

let
  secretsPath = config.services.kubernetes.secretsPath;

  renewScript = pkgs.writeShellScript "kube-cert-renew" ''
    set -euo pipefail
    export PATH="${lib.makeBinPath [ pkgs.openssl pkgs.coreutils pkgs.findutils pkgs.gnugrep pkgs.systemd ]}"

    SECRETS="${secretsPath}"
    RENEW_THRESHOLD_SECONDS=$((7 * 24 * 3600))  # 7 days
    RENEWED=0

    if [ ! -d "$SECRETS" ]; then
      echo "kube-cert-renew: secrets dir $SECRETS not found, skipping"
      exit 0
    fi

    NOW=$(date +%s)

    for cert in "$SECRETS"/*.pem; do
      # Skip key files and CA cert
      case "$cert" in
        *-key.pem) continue ;;
      esac

      # Skip if not a valid certificate
      if ! openssl x509 -in "$cert" -noout 2>/dev/null; then
        continue
      fi

      EXPIRY=$(openssl x509 -in "$cert" -noout -enddate 2>/dev/null | sed 's/notAfter=//')
      if [ -z "$EXPIRY" ]; then
        continue
      fi

      EXPIRY_EPOCH=$(date -d "$EXPIRY" +%s 2>/dev/null || echo 0)
      REMAINING=$((EXPIRY_EPOCH - NOW))

      if [ "$REMAINING" -lt "$RENEW_THRESHOLD_SECONDS" ]; then
        CERT_NAME=$(basename "$cert")
        echo "kube-cert-renew: $CERT_NAME expires in $((REMAINING / 3600))h, removing for re-issue"
        # Remove cert and its corresponding key
        rm -f "$cert"
        KEY_FILE="''${cert%.pem}-key.pem"
        rm -f "$KEY_FILE"
        RENEWED=$((RENEWED + 1))
      fi
    done

    if [ "$RENEWED" -gt 0 ]; then
      echo "kube-cert-renew: removed $RENEWED expired/expiring cert(s), restarting certmgr"
      systemctl restart certmgr.service

      # Wait for certmgr to re-issue certs (up to 60s)
      for i in $(seq 1 60); do
        MISSING=0
        for cert in kubelet kubelet-client kube-proxy-client flannel-client; do
          if [ ! -f "$SECRETS/$cert.pem" ]; then
            MISSING=$((MISSING + 1))
          fi
        done
        if [ "$MISSING" -eq 0 ]; then
          break
        fi
        sleep 1
      done

      echo "kube-cert-renew: restarting kubernetes services"
      systemctl restart kubelet.service || true
      systemctl restart kube-proxy.service || true
      systemctl restart flannel.service || true
    else
      echo "kube-cert-renew: all certs valid for >7 days, no action needed"
    fi
  '';
in
{
  systemd.services.kube-cert-renew = {
    description = "Kubernetes certificate renewal safety net";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = renewScript;
    };
    after = [ "network-online.target" "cfssl.target" ];
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
