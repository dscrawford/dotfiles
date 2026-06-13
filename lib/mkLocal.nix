{ nixpkgs, home-manager, sops-nix, lib, claudeSkills, ... }:
{ hostname, username, system ? "x86_64-linux", gitUser ? null, enableSecrets ? true, homeModules ? [ ../shared/home.nix ], extraModules ? [] }: nixpkgs.lib.nixosSystem {
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

    ../shared/common.nix
    ../shared/boot-common.nix
    ../shared/local-common.nix
    ../hosts/local/local.nix
    ../hosts/local/hardware-configuration.nix

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
}
