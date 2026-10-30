{ nixpkgs, sops-nix, ... }:
{ hostname, ip, netInterface ? "eno1", extraModules ? [] }:
let
  kubeNodes = {
    node1 = "192.168.0.2";
    node2 = "192.168.0.4";
    node3 = "192.168.0.6";
  };
in
nixpkgs.lib.nixosSystem rec {
  system = "x86_64-linux";
  specialArgs = {
    inherit hostname ip netInterface kubeNodes;
    kubeMasterIP = kubeNodes.node1;
    kubeMasterHostname = "api.kube";
    kubeMasterAPIServerPort = 6443;
    kubeApiVIP = "192.168.0.10";
  };
  modules = [
    sops-nix.nixosModules.sops
    ../shared/common.nix
    ../shared/server-common.nix
    ../shared/users.nix
    ../shared/boot-common.nix
    ../shared/nix-gc.nix
  ] ++ extraModules;
}
