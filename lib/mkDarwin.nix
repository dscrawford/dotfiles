{ home-manager, sops-nix, nix-darwin, darwin-emacs, lib, claudeSkills, ... }:
{ hostname, username, system, gitUser ? null, enableSecrets ? false, homeModules ? [ ../shared/home.nix ], extraModules ? [] }: nix-darwin.lib.darwinSystem {
  inherit system;
  specialArgs = {
    inherit hostname username;
  };
  modules = [
    { nixpkgs.overlays = [
        darwin-emacs.overlays.emacs
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
    ../shared/darwin-common.nix

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
}
