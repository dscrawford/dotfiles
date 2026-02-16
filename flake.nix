# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, sops-nix }: 
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
        ./boot-common.nix
      ] ++ extraModules;
    };

    mkLocal = { hostname, username, extraModules ? [] }: nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        inherit hostname username;
      };
      modules = [
        ./common.nix
        ./boot-common.nix
        ./local-common.nix
        ./hosts/local/local.nix
        ./hosts/local/hardware-configuration.nix
        
        # Sops integration
        sops-nix.nixosModules.sops
        
        # Home Manager integration
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.users.${username} = import ./hosts/local/home.nix;
          home-manager.extraSpecialArgs = { inherit hostname username; };
          home-manager.sharedModules = [
            sops-nix.homeManagerModules.sops
          ];
        }
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
      local = mkLocal {
        hostname = "nixos";
        username = "daniel";
        extraModules = [];
      };
    };
  };
}
