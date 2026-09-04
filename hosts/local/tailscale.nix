# Only the `local` host imports this (flake.nix): the terminal builds share
# hosts/local/local.nix and must stay buildable without the secrets submodule.
{ config, ... }:

{
  sops = {
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    secrets.local.sopsFile = ../../secrets/tailscale.yaml;
  };
  services.tailscale = {
    authKeyFile = config.sops.secrets.local.path;
    extraUpFlags = [ "--hostname=desktop" "--accept-dns=false" ];
  };
}
