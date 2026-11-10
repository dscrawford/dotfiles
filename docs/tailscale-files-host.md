# GOTG bytes over the tailnet

The catalog's byte host was `gotg-files.dcraw.net`: caddy in the `gotg-library` pod
behind a ProtonVPN port-forward that moved on every reconnect and ran at ~2 MB/s. On
the tailnet the library's NodePort is reached at a node's tailscale IP over WireGuard,
with nothing exposed to the internet.

## State (2026-09-04, done)

- node1 100.70.210.123, node2 100.107.126.30, node3 100.74.183.90. LAN peers connect
  direct (`tailscale status`: `direct 192.168.0.x:41641`), not via DERP.
- `files_urls` lists the tailnet NodePort `http://100.70.210.123:30780` first, then the
  VPN `https://gotg-files.dcraw.net:<port>` (`files_url` stays the latter for old
  clients). Clients probe each once per download with a 3 s connect timeout, so
  machines off the tailnet still download via the VPN.
- node2 → node1, one 50 MB member: 10.7 MB/s on the tailnet vs 34 MB/s bare LAN (NFS
  streaming caps the LAN; WireGuard on the Gen8 Xeons caps the tailnet). 5x the VPN.

## Joining

Each node joins at activation: `shared/server-common.nix` passes
`services.tailscale.authKeyFile` a sops secret named after the host, decrypted with the
node's SSH host key (`ssh-to-age` of `/etc/ssh/ssh_host_ed25519_key`; recipients in
`secrets/.sops.yaml`). Keys are in `secrets/tailscale.yaml`, one per host.

```bash
# Admin console → Settings → Keys → Generate: pre-authorized, not reusable.
sops secrets/tailscale.yaml        # node1:, node2:, node3:, local:
git -C secrets commit -am "feat: tailscale auth keys for the nodes"
deploy-nodes                       # passes ?submodules=1
```

State persists in `/var/lib/tailscale`; the key is read again only after a reinstall,
so an expired key unjoins nothing. A reinstalled node has a new host key: rederive its
age recipient, replace it in `.sops.yaml`, run `sops updatekeys secrets/tailscale.yaml`.

The desktop uses `hosts/local/tailscale.nix`, key `local` (`local`, `terminal` and
`terminal-arm` all have hostname `nixos`), device name `desktop`; its recipient is the
desktop's host key, so it builds with `'.?submodules=1#local'`. Terminal builds have no
key: run `sudo tailscale up` once.

## Catalog side

`~/Documents/Kubernetes/config/GOTG/api.yaml` has NodePort Service
`gotg-library-tailnet` on TCP 30780 (inside the nodes' open 30500–30799 range):

```bash
IP=$(ssh node1 tailscale ip -4)
kubectl set env deploy/gotg-library GOTG_FILES_URL="http://$IP:30780" GOTG_FILES_PORT_FILE-
```

Mirror both values into `api.yaml`. Plain HTTP is fine: the tailnet encrypts it. The
gluetun/caddy/files-ddns sidecars can go once nothing uses `gotg-files.dcraw.net`.
Clients pick up the host on `gotg refresh` (a failed download re-reads the catalog).
Cluster QA pods are unaffected: they use the in-cluster service and the mounted library.
