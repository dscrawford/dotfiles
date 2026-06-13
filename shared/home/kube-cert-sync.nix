# shared/home/kube-cert-sync.nix
# Sync cluster-admin certs from the Kubernetes master (Linux only).
{ lib, pkgs, username, ... }:

let
  isDarwin = pkgs.stdenv.isDarwin;
  isLinux = pkgs.stdenv.isLinux;
  homeDir = if isDarwin then "/Users/${username}" else "/home/${username}";
in
{
  # Sync cluster-admin certs from the Kubernetes master (Linux only).
  # Certs are issued by CFSSL with easyCerts; this pulls them to ~/.kube/certs
  # so kubectl works from the local desktop.
  systemd.user.services.kube-cert-sync = lib.mkIf isLinux {
    Unit.Description = "Sync kubectl certs from Kubernetes master";
    Service = {
      Type = "oneshot";
      ExecStart = let
        script = pkgs.writeShellApplication {
          name = "kube-cert-sync";
          runtimeInputs = [ pkgs.openssh pkgs.openssl pkgs.coreutils ];
          text = ''
            KUBE_DIR="${homeDir}/.kube/certs"
            MASTER="host@node1"
            SECRETS="/var/lib/kubernetes/secrets"
            CERTS="ca.pem cluster-admin.pem cluster-admin-key.pem"

            mkdir -p "$KUBE_DIR"

            for cert in $CERTS; do
              # shellcheck disable=SC2029
              ssh "$MASTER" "sudo cat $SECRETS/$cert" > "$KUBE_DIR/$cert.tmp"
              mv "$KUBE_DIR/$cert.tmp" "$KUBE_DIR/$cert"
              chmod 600 "$KUBE_DIR/$cert"
            done

            EXPIRY=$(openssl x509 -in "$KUBE_DIR/cluster-admin.pem" -noout -enddate)
            echo "kube-cert-sync: certs updated, ''${EXPIRY#notAfter=}"
          '';
        };
      in "${script}/bin/kube-cert-sync";
    };
  };

  systemd.user.timers.kube-cert-sync = lib.mkIf isLinux {
    Unit.Description = "Weekly kubectl cert sync from Kubernetes master";
    Timer = {
      OnCalendar = "weekly";
      RandomizedDelaySec = "1h";
      Persistent = true;
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
