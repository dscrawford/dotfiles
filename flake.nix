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
    nix-darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, sops-nix, nix-darwin }:
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
        ./shared/common.nix
        ./shared/server-common.nix
        ./shared/users.nix
        ./shared/boot-common.nix
      ] ++ extraModules;
    };

    mkLocal = { hostname, username, system ? "x86_64-linux", homeModules ? [ ./shared/home.nix ], extraModules ? [] }: nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = {
        inherit hostname username;
      };
      modules = [
        ./shared/common.nix
        ./shared/boot-common.nix
        ./shared/local-common.nix
        ./hosts/local/local.nix
        ./hosts/local/hardware-configuration.nix

        # Sops integration
        sops-nix.nixosModules.sops

        # Home Manager integration
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.users.${username} = {
            imports = homeModules;
          };
          home-manager.extraSpecialArgs = { inherit hostname username; };
          home-manager.sharedModules = [
            sops-nix.homeManagerModules.sops
          ];
        }
      ] ++ extraModules;
    };

    mkDarwin = { hostname, username, system, homeModules ? [ ./shared/home.nix ], extraModules ? [] }: nix-darwin.lib.darwinSystem {
      inherit system;
      specialArgs = {
        inherit hostname username;
      };
      modules = [
        ./shared/darwin-common.nix

        # Sops integration
        sops-nix.darwinModules.sops

        # Home Manager integration
        home-manager.darwinModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.users.${username} = {
            imports = homeModules;
          };
          home-manager.extraSpecialArgs = { inherit hostname username; };
          home-manager.sharedModules = [
            sops-nix.homeManagerModules.sops
          ];
        }
      ] ++ extraModules;
    };
  in {
    lib = { inherit mkServer mkLocal mkDarwin; };

    nixosConfigurations = {
      node1 = mkServer {
        hostname = "node1";
        ip = "192.168.0.2";
        extraModules = [
          ./hosts/node1/hardware-configuration.nix
          ./hosts/node1/boot.nix
          ./shared/kubernetes.nix
          ./shared/iscsi.nix
        ];
      };
      node2 = mkServer {
        hostname = "node2";
        ip = "192.168.0.4";
        extraModules = [
          ./hosts/node2/hardware-configuration.nix
          ./hosts/node2/boot.nix
          ./shared/kubernetes.nix
          ./shared/iscsi.nix
        ];
      };
      local = mkLocal {
        hostname = "nixos";
        username = "daniel";
        homeModules = [ ./shared/home.nix ./shared/sway.nix ./shared/gaming.nix ];
      };
      terminal = mkLocal {
        hostname = "nixos";
        username = "daniel";
      };
      terminal-arm = mkLocal {
        hostname = "nixos";
        username = "daniel";
        system = "aarch64-linux";
      };
    };
    darwinConfigurations = {
      terminal-darwin-arm = mkDarwin {
        hostname = "nixos";
        username = "daniel";
        system = "aarch64-darwin";
      };
      terminal-darwin-x86 = mkDarwin {
        hostname = "nixos";
        username = "daniel";
        system = "x86_64-darwin";
      };
    };
  };
}
