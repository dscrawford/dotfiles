# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }: 
  let
    mkServer = { hostname, ip, extraModules ? [] }: nixpkgs.lib.nixosSystem rec {
      system = "x86_64-linux";
      specialArgs = {
        inherit hostname ip;
        kubeMasterIP = "192.168.0.2";
        kubeMasterHostname = "api.kube";
        kubeMasterAPIServerPort = 6443;
      };
      modules = [
        ./common.nix
        ./server-common.nix
        ./users.nix
      ] ++ extraModules;
    };
  in {
    nixosConfigurations = {
      node1 = mkServer {
        hostname = "node1";
        ip = "192.168.0.2";
        extraModules = [
          ./hosts/node1/hardware-configuration.nix
          ./hosts/node1/boot.nix
          ./kubernetes.nix
          ./iscsi.nix
        ];
      };
      node2 = mkServer {
        hostname = "node2";
        ip = "192.168.0.4";
        extraModules = [
          ./hosts/node2/hardware-configuration.nix
          ./hosts/node2/boot.nix
          ./kubernetes.nix
          ./iscsi.nix
        ];
      };
    };
  };
}
