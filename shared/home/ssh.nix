# shared/home/ssh.nix
# SSH configuration
{ ... }:

{
  # SSH — force xterm-256color since eat-truecolor is rarely available on remote hosts
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    settings."*" = {
      SetEnv.TERM = "xterm-256color";
    };
    # GitHub over SSH; this is the key registered as dscrawford.
    settings."github.com" = {
      User = "git";
      IdentityFile = "~/.ssh/id_rsa_bitwarden";
      IdentitiesOnly = true;
    };
    # Cluster nodes: the only key in users.nix's authorizedKeys that exists
    # here is the bitwarden one, and the LAN DNS does not resolve node3.
    # kube-cert-sync and deploy-nodes both rely on these aliases.
    settings."node1 node2 node3" = {
      User = "host";
      IdentityFile = "~/.ssh/id_rsa_bitwarden";
      IdentitiesOnly = true;
    };
    settings."node1".HostName = "192.168.0.2";
    settings."node2".HostName = "192.168.0.4";
    settings."node3".HostName = "192.168.0.6";
  };
}
