# GOTG bytes over the tailnet

The catalog's byte host used to be `gotg-files.dcraw.net`: caddy inside the
`gotg-library` pod, reached through a ProtonVPN port-forward that moves on
every reconnect and measured about 2 MB/s. The tailnet replaces that hop for
every machine on it: the library's NodePort is addressed by a node's tailscale
IP, the traffic is WireGuard end to end, and nothing about the house is
exposed to the internet.

## State on 2026-09-04

- `tailscaled` runs on node1/node2/node3 (`shared/server-common.nix`) but no
  node has ever been logged in: `tailscale status` says NeedsLogin on all
  three. `--accept-dns=false` on the nodes is right; they never resolve.
- The desktop had no tailscale at all; `shared/local-common.nix` now enables
  it. Join with `sudo tailscale up` after the rebuild.

## Joining the nodes

Each node prints its own login link:

```bash
ssh node1 'tailscale status'   # "Log in at: https://login.tailscale.com/a/..."
ssh node2 'tailscale status'
ssh node3 'sudo tailscale up --hostname=node3 --accept-dns=false'
```

Open each link as the tailnet admin. The login persists in
`/var/lib/tailscale` across rebuilds and reboots. To make a node re-join on
its own after a reinstall, put a reusable, pre-authorized auth key in sops and
set `services.tailscale.authKeyFile`; the flags in `extraUpFlags` already
carry the hostname.

## Pointing the catalog at it

`~/Documents/Kubernetes/config/GOTG/api.yaml` carries a NodePort Service,
`gotg-library-tailnet`, on TCP 30780 — inside the nodes' allowed 30500–30799
range, so no firewall change. Once node1 has a tailscale IP:

```bash
IP=$(ssh node1 tailscale ip -4)
kubectl set env deploy/gotg-library GOTG_FILES_URL="http://$IP:30780" GOTG_FILES_PORT_FILE-
```

and mirror the two values into `api.yaml`. Plain HTTP is fine here: the
tailnet encrypts it, and the bearer token never crosses anything else. The
gluetun/caddy/files-ddns sidecars can go once nobody depends on
`gotg-files.dcraw.net`; until then they cost nothing.

Clients pick the new host up on their next `gotg refresh` (a download that
fails re-reads the catalog on its own). QA pods on the cluster are unaffected:
they set `GOTG_FILES_URL` to the in-cluster service and copy from the mounted
library.
