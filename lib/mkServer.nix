{ nixpkgs, ... }:
{ hostname, ip, netInterface ? "eno1", extraModules ? [] }: nixpkgs.lib.nixosSystem rec {
  system = "x86_64-linux";
  specialArgs = {
    inherit hostname ip netInterface;
    kubeMasterIP = "192.168.0.2";
    kubeMasterHostname = "api.kube";
    kubeMasterAPIServerPort = 6443;
  };
  modules = [
    ../shared/common.nix
    ../shared/server-common.nix
    ../shared/users.nix
    ../shared/boot-common.nix
  ] ++ extraModules;
}
