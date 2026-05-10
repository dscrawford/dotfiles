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
    everything-claude-code = {
      url = "github:affaan-m/everything-claude-code";
      flake = false;
    };
    cli-anything = {
      url = "github:HKUDS/CLI-Anything";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, home-manager, sops-nix, nix-darwin, everything-claude-code, cli-anything }:
  let
    inherit (nixpkgs) lib;

    # Claude Code skill sources — add new repos here
    # Each entry: { src, skillsDir } where skillsDir is a function from src to the skills directory
    claudeSkills = {
      everything-claude-code = {
        src = everything-claude-code;
        # .agents/skills/<name>/SKILL.md
        findSkills = src: src + "/.agents/skills";
      };
      cli-anything = {
        src = cli-anything;
        # <app>/agent-harness/cli_anything/<app>/skills/SKILL.md
        # Flattened: scan each top-level app dir for the nested skills path
        findSkills = null;  # uses custom scanner in home.nix
      };
    };
    mkServer = { hostname, ip, netInterface ? "eno1", extraModules ? [] }: nixpkgs.lib.nixosSystem rec {
      system = "x86_64-linux";
      specialArgs = {
        inherit hostname ip netInterface;
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

    mkLocal = { hostname, username, system ? "x86_64-linux", gitUser ? null, enableSecrets ? true, homeModules ? [ ./shared/home.nix ], extraModules ? [] }: nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = {
        inherit hostname username;
      };
      modules = [
        # FIXME: remove once nixpkgs fixes openldap test017-syncreplication-refresh
        # Upstream bug: flaky syncrepl timing in check phase
        { nixpkgs.overlays = [(final: prev: {
          openldap = prev.openldap.overrideAttrs (old: { doCheck = false; });
        })]; }

        ./shared/common.nix
        ./shared/boot-common.nix
        ./shared/local-common.nix
        ./hosts/local/local.nix
        ./hosts/local/hardware-configuration.nix

        # Home Manager integration
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.users.${username} = {
            imports = homeModules;
          };
          home-manager.extraSpecialArgs = { inherit hostname username gitUser enableSecrets claudeSkills; };
          home-manager.sharedModules = lib.optionals enableSecrets [
            sops-nix.homeManagerModules.sops
          ];
        }
      ] ++ lib.optionals enableSecrets [
        sops-nix.nixosModules.sops
      ] ++ extraModules;
    };

    mkDarwin = { hostname, username, system, gitUser ? null, enableSecrets ? false, homeModules ? [ ./shared/home.nix ], extraModules ? [] }: nix-darwin.lib.darwinSystem {
      inherit system;
      specialArgs = {
        inherit hostname username;
      };
      modules = [
        { nixpkgs.overlays = [
            # Clang 19 strictness breaks ffmpeg-dependent Python packages on Darwin.
            # Force gnu17 for av (PyAV) and imageio builds until upstream fixes land.
            (final: prev: {
              pythonPackagesExtensions = (prev.pythonPackagesExtensions or []) ++ [
                (pyfinal: pyprev: {
                  av = pyprev.av.overrideAttrs (old: {
                    env = (old.env or {}) // {
                      NIX_CFLAGS_COMPILE = (old.env.NIX_CFLAGS_COMPILE or "") + " -std=gnu17";
                    };
                  });
                  imageio = pyprev.imageio.overrideAttrs (old: {
                    env = (old.env or {}) // {
                      NIX_CFLAGS_COMPILE = (old.env.NIX_CFLAGS_COMPILE or "") + " -std=gnu17";
                    };
                  });
                })
              ];
            })
          ]; }
        ./shared/darwin-common.nix

        # Home Manager integration
        home-manager.darwinModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.backupFileExtension = "hm-backup";
          home-manager.users.${username} = {
            imports = homeModules;
          };
          home-manager.extraSpecialArgs = { inherit hostname username gitUser enableSecrets claudeSkills; };
          home-manager.sharedModules = lib.optionals enableSecrets [
            sops-nix.homeManagerModules.sops
          ];
        }
      ] ++ lib.optionals enableSecrets [
        sops-nix.darwinModules.sops
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
          ./shared/kube-cert-renew.nix
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
          ./shared/kube-cert-renew.nix
          ./shared/iscsi.nix
        ];
      };
      node3 = mkServer {
        hostname = "node3";
        ip = "192.168.0.6";
        netInterface = "enp5s0";
        extraModules = [
          ./hosts/node3/hardware-configuration.nix
          ./hosts/node3/boot.nix
          ./hosts/node3/nvidia.nix
          ./hosts/node3/storage.nix
          ./shared/kubernetes.nix
          ./shared/kube-cert-renew.nix
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
