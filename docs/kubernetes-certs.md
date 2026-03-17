# Kubernetes Certificate Management

NixOS `easyCerts` generates all cluster TLS certificates via CFSSL running on the master node (node1). Certificates are valid for 30 days and are auto-renewed by `certmgr`.

## Architecture

```
node1 (master)                    node2/node3 (workers)
├── /var/lib/cfssl/               ├── /var/lib/kubernetes/secrets/
│   ├── ca.pem          ──────>  │   ├── ca.pem
│   ├── ca-key.pem               │   ├── apitoken.secret
│   ├── cfssl.pem (TLS cert)     │   ├── kubelet-client.pem
│   ├── cfssl-key.pem            │   ├── kubelet-client-key.pem
│   └── apitoken.secret ──────>  │   ├── kube-proxy-client.pem
│                                │   ├── flannel-client.pem
├── /var/lib/kubernetes/secrets/  │   └── ...
│   ├── kube-scheduler-client.pem│
│   ├── kube-controller-manager-client.pem
│   ├── kube-apiserver-kubelet-client.pem
│   ├── service-account.pem
│   └── ...
│
└── CFSSL server (port 8888) <── certmgr requests certs using apitoken
```

## Services

| Service | Node | Purpose |
|---------|------|---------|
| `cfssl` | master | CA server — signs certificate requests on port 8888 |
| `certmgr` | all | Requests and renews client certs from CFSSL |
| `kube-certmgr-bootstrap` | all | Seeds `ca.pem` and `apitoken.secret` on first boot |

## Checking Certificate Expiry

```bash
# On any node — check all certs
sudo find /var/lib/kubernetes/secrets -name "*.pem" -exec \
  openssl x509 -in {} -noout -subject -enddate \;

# On master — check CFSSL server cert
sudo openssl x509 -in /var/lib/cfssl/cfssl.pem -noout -dates

# Check CFSSL cert SANs (must include 192.168.0.2 for workers to connect)
sudo openssl x509 -in /var/lib/cfssl/cfssl.pem -noout -text | grep -A1 "Subject Alternative"
```

## Renewing Expired Certificates

### Full cluster renewal (master + workers)

When certs expire, the entire chain must be regenerated starting from the master.

#### Step 1: Regenerate CFSSL CA and certs on node1 (master)

```bash
# SSH to node1
ssh host@192.168.0.2

# Delete old CFSSL certs (CA + server cert)
sudo rm /var/lib/cfssl/cfssl.pem /var/lib/cfssl/cfssl-key.pem /var/lib/cfssl/cfssl.csr

# Restart CFSSL to regenerate server cert with correct SANs
sudo systemctl restart cfssl
sleep 5

# Verify new cert includes the master IP
sudo openssl x509 -in /var/lib/cfssl/cfssl.pem -noout -text | grep -A1 "Subject Alternative"
# Should show: IP Address:127.0.0.1, IP Address:192.168.0.2

# Delete old kubernetes client certs
sudo rm -f /var/lib/kubernetes/secrets/*.pem
sudo rm -f /var/lib/kubernetes/secrets/*-key.pem

# Copy fresh CA into kubernetes secrets
sudo cp /var/lib/cfssl/ca.pem /var/lib/kubernetes/secrets/ca.pem

# Restart certmgr to regenerate all client certs
sudo systemctl restart certmgr
sleep 20

# Verify certs were created
ls /var/lib/kubernetes/secrets/*.pem
# Should show: kubelet-client.pem, kube-scheduler-client.pem,
#   kube-controller-manager-client.pem, kube-proxy-client.pem,
#   kube-apiserver-kubelet-client.pem, service-account.pem, etc.

# Restart kubernetes services
sudo systemctl restart kube-apiserver
sudo systemctl restart kube-controller-manager
sudo systemctl restart kube-scheduler
sudo systemctl restart kubelet
```

#### Step 2: Regenerate certs on each worker node

Repeat this on each worker (node2, node3, etc.):

```bash
# SSH to the worker
ssh host@192.168.0.4  # or 192.168.0.6 for node3

# Delete old secrets
sudo rm -rf /var/lib/kubernetes/secrets
sudo mkdir -p /var/lib/kubernetes/secrets

# Copy CA and API token from master
ssh host@192.168.0.2 "sudo cat /var/lib/cfssl/ca.pem" | \
  sudo tee /var/lib/kubernetes/secrets/ca.pem > /dev/null
ssh host@192.168.0.2 "sudo cat /var/lib/cfssl/apitoken.secret" | \
  sudo tee /var/lib/kubernetes/secrets/apitoken.secret > /dev/null

# Bootstrap and regenerate certs
sudo systemctl restart kube-certmgr-bootstrap
sudo systemctl restart certmgr
sleep 20

# Verify
ls /var/lib/kubernetes/secrets/*.pem

# Restart kubelet
sudo systemctl restart kubelet
```

#### Step 3: Verify cluster health

```bash
# On master
kubectl get nodes
# All nodes should show Ready
```

## Troubleshooting

### certmgr fails with "certificate signed by unknown authority"

The `ca.pem` in `/var/lib/kubernetes/secrets/` doesn't match the CA that signed `cfssl.pem`. Fix:

```bash
sudo cp /var/lib/cfssl/ca.pem /var/lib/kubernetes/secrets/ca.pem  # on master
# Or from a worker:
ssh host@192.168.0.2 "sudo cat /var/lib/cfssl/ca.pem" | \
  sudo tee /var/lib/kubernetes/secrets/ca.pem > /dev/null
sudo systemctl restart certmgr
```

### certmgr fails with "authentication error" on authsign

The API token doesn't match. The CFSSL server reads the token at startup, so both the token file and the service must be in sync:

```bash
# Copy fresh token from master
ssh host@192.168.0.2 "sudo cat /var/lib/cfssl/apitoken.secret" | \
  sudo tee /var/lib/kubernetes/secrets/apitoken.secret > /dev/null

# If still failing, restart cfssl on master to reload the token
ssh host@192.168.0.2 "sudo systemctl restart cfssl"

# Then restart certmgr on the worker
sudo systemctl restart certmgr
```

### CFSSL cert only has 127.0.0.1 in SANs (workers can't connect)

The `pki.cfsslAPIExtraSANs` option in `kubernetes.nix` adds the master IP to the CFSSL cert. If the cert was generated before this option was set:

```bash
# On master — delete and regenerate
sudo rm /var/lib/cfssl/cfssl.pem /var/lib/cfssl/cfssl-key.pem /var/lib/cfssl/cfssl.csr
sudo systemctl restart cfssl
```

### kubelet fails with "unable to read client-cert"

The client cert PEM files are missing. Certmgr hasn't generated them yet:

```bash
sudo systemctl status certmgr  # check if running
sudo journalctl -u certmgr -n 20 --no-pager -o cat  # check for errors
```

### /var/lib/kubernetes/secrets doesn't exist

NixOS doesn't auto-create this directory if it was deleted. Create it manually:

```bash
sudo mkdir -p /var/lib/kubernetes/secrets
```

Then follow the worker renewal steps above.

## Configuration Reference

The CFSSL SAN configuration lives in `shared/kubernetes.nix`:

```nix
services.kubernetes = {
  easyCerts = true;
  pki.cfsslAPIExtraSANs = lib.mkIf isMaster [ kubeMasterIP ];
};
```

This ensures the CFSSL server cert includes both `127.0.0.1` (for local master connections) and `192.168.0.2` (for worker connections).
