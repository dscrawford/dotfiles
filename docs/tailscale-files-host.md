# GOTG bytes over the tailnet

The catalog's byte host used to be `gotg-files.dcraw.net`: caddy inside the
`gotg-library` pod, reached through a ProtonVPN port-forward that moves on
every reconnect and measured about 2 MB/s. The tailnet replaces that hop for
every machine on it: the library's NodePort is addressed by a node's tailscale
IP, the traffic is WireGuard end to end, and nothing about the house is
exposed to the internet.

## State on 2026-09-04 (evening: done)

- node1 100.70.210.123, node2 100.107.126.30, node3 100.74.183.90 — joined
  through their sops auth keys. Peers on the LAN connect direct
  (`tailscale status` shows `direct 192.168.0.x:41641`), not via DERP.
- The catalog advertises two hosts in `files_urls`: the tailnet NodePort
  `http://100.70.210.123:30780` first, the VPN-fronted
  `https://gotg-files.dcraw.net:<port>` behind it (`files_url` stays that
  one, for older clients). A client probes each once per download with a
  3 s connect timeout and takes the first that answers, so a machine off
  the tailnet — a friend's, or this desktop before it joined — still
  downloads, just through the VPN.
- Measured node2 → node1 for one 50 MB member: 10.7 MB/s over the tailnet
  against 34 MB/s on the bare LAN (the library's NFS-backed streaming is the
  LAN ceiling; WireGuard on the Gen8 Xeons is the tailnet one). Five times
  the ProtonVPN path, and no port that moves.
- The desktop joins the same way the nodes do, from the `local` key in
  `secrets/tailscale.yaml` (`hosts/local/tailscale.nix`), as device `desktop`.

## Joining the nodes

Each node joins on its own at activation: `shared/server-common.nix` hands
`services.tailscale.authKeyFile` a sops-nix secret named after the host,
decrypted with the node's own SSH host key (`ssh-to-age` of
`/etc/ssh/ssh_host_ed25519_key`; the three recipients are in
`secrets/.sops.yaml`). The keys live in `secrets/tailscale.yaml`, in the
private submodule, one entry per node.

```bash
# Tailscale admin console → Settings → Keys → Generate: pre-authorized,
# not reusable, tag as you like. One per node, then:
sops secrets/tailscale.yaml        # paste into node1:, node2:, node3:, local:
git -C secrets commit -am "feat: tailscale auth keys for the nodes"
deploy-nodes                       # passes ?submodules=1 so the file is seen
```

A node that has joined keeps its state in `/var/lib/tailscale`; the key is
only read again if that state is gone (a reinstall), so an expired key does
not unjoin anything. A reinstalled node has a new host key: rederive its age
recipient, replace it in `.sops.yaml`, `sops updatekeys secrets/tailscale.yaml`.

The desktop follows the same pattern from `hosts/local/tailscale.nix`, keyed
`local` (the flake host; `local`, `terminal`, and `terminal-arm` all share the
hostname `nixos`) and named `desktop` on the tailnet. Its recipient in
`.sops.yaml` is the desktop's own host key, so a rebuild needs
`'.?submodules=1#local'`. Terminal builds have no key: `sudo tailscale up`
once.

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
