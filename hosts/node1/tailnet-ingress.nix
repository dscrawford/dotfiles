# node1 serves the cluster ingress on its tailscale address (KubeServer
# config/ingress/, Service ingress-nginx-tailnet). Keep the client's address
# visible to nginx: tailscaled masquerades forwarded traffic by default.
{ ... }:

{
  services.tailscale.extraSetFlags = [ "--snat-subnet-routes=false" ];

  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 80 443 ];
}
