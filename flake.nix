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
    darwin-emacs = {
      url = "github:nix-giant/nix-darwin-emacs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    lsfg-vk-flake = {
      url = "github:pabloaul/lsfg-vk-flake/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    everything-claude-code = {
      url = "github:affaan-m/everything-claude-code";
      flake = false;
    };
    cli-anything = {
      url = "github:HKUDS/CLI-Anything";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, home-manager, sops-nix, nix-darwin, darwin-emacs, lsfg-vk-flake, everything-claude-code, cli-anything }:
  let
    builders = import ./lib {
      inherit nixpkgs home-manager sops-nix nix-darwin darwin-emacs
        everything-claude-code cli-anything;
    };
    inherit (builders) mkServer mkLocal mkDarwin;
    kubeNode = { hostname, ip, netInterface ? "eno1", extraModules ? [] }: mkServer {
      inherit hostname ip netInterface;
      extraModules = [
        (./hosts + "/${hostname}/hardware-configuration.nix")
        (./hosts + "/${hostname}/boot.nix")
        ./shared/kubernetes.nix
        ./shared/kube-cert-renew.nix
        ./shared/kube-stale-mount-recovery.nix
        ./shared/iscsi.nix
      ] ++ extraModules;
    };
  in {
    lib = { inherit mkServer mkLocal mkDarwin; };

    nixosConfigurations = {
      node1 = kubeNode { hostname = "node1"; ip = "192.168.0.2"; };
      node2 = kubeNode { hostname = "node2"; ip = "192.168.0.4"; };
      node3 = kubeNode {
        hostname = "node3";
        ip = "192.168.0.6";
        netInterface = "enp5s0";
        extraModules = [ ./hosts/node3/nvidia.nix ./hosts/node3/storage.nix ];
      };
      local = mkLocal {
        hostname = "nixos";
        username = "daniel";
        homeModules = [
          ./shared/home ./shared/sway ./shared/gaming.nix ./shared/easyeffects.nix
          # Ollama daemon itself comes from shared/home/ollama.nix; only the
          # GPU package choice is desktop-specific.
          ({ pkgs, ... }: { services.ollama.package = pkgs.ollama-cuda; })
        ];
        extraModules = [
          ./shared/vr.nix

          # Needs Lossless Scaling installed via Steam; activate per-game with
          # `ENABLE_LSFG=1 %command%` in the launch options.
          lsfg-vk-flake.nixosModules.default
          { services.lsfg-vk = { enable = true; ui.enable = true; }; }
        ];
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
