# hosts/node1/tailnet-ingress.nix
# node1 fronts hub.dcraw.net for the tailnet: KubeServer's `ingress-nginx-tailnet`
# Service publishes the ingress controller on node1's tailscale address
# (100.70.210.123) with externalTrafficPolicy=Local, and every hub Ingress
# allowlists the owner's devices by their tailscale /32. That allowlist only
# works if nginx sees the device's address, and two things rewrite it:
#
#  - kube-proxy, unless the Service is `Local` (handled in KubeServer);
#  - tailscaled, which on Linux MASQUERADEs every packet it forwards off
#    tailscale0 by default (--snat-subnet-routes=true), whether or not the
#    node advertises routes. The DNAT to the controller pod makes the hub
#    traffic "forwarded", so without this flag nginx logs node1's own 100.x
#    for every client. Design: KubeServer docs/research/2026-11-10-hub-dcraw-net.md.
#
# The firewall rule covers the INPUT path (hostNetwork/host-port variants and
# anything else the Service might be switched to); the DNAT'd path is FORWARD,
# which tailscaled already accepts from tailscale0.
{ ... }:

{
  services.tailscale.extraSetFlags = [ "--snat-subnet-routes=false" ];

  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 80 443 ];
}
