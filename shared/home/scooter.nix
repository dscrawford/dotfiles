# shared/home/scooter.nix
# The Scooter server scooter-mode (wired in emacs/scooter.nix) talks to.
# Set url to "" to keep Scooter out of Emacs and the agent picker.
# local.enable adds scooter-local, which runs one on this machine.
{ config, lib, pkgs, scooter, ... }:

{
  options.my.scooter = {
    local.enable = lib.mkEnableOption "scooter-local: Scooter in a k3d cluster on this machine (needs Docker)";
    url = lib.mkOption {
      type = lib.types.str;
      default = "https://scooter.dcraw.net";
      example = "https://scooter.example.com";
      description = ''
        Scooter UI origin. Behind oauth2-proxy: scooter-mode reads its
        session cookie (cookieName) from your browser (browser) and keeps
        it in auth-source.
      '';
    };
    browser = lib.mkOption {
      type = lib.types.str;
      default = "any";
      example = "firefox";
      description = ''
        Which browser's session scooter-mode signs in with: "any" reads
        every browser scooter-mode knows (Firefox, Chromium, Chrome,
        Brave, LibreWolf) and opens the sign-in page with the default
        one; a name (firefox, chromium, brave, ...) reads and opens only
        that browser.
      '';
    };
    cookieName = lib.mkOption {
      type = lib.types.str;
      default = "__Host-scooter_oauth2";
      example = "_oauth2_proxy";
      description = ''
        oauth2-proxy's --cookie-name at url (KubeServer
        config/scooter/oauth2-proxy.yaml). scooter-mode looks for this
        cookie in your browser (browser) and sends it.
      '';
    };
  };

  # The fork's images: its CI publishes every tag its main renders to its own
  # ghcr, while the default prefix (chadac-me) lacks the ones the fork changed.
  config = lib.mkIf config.my.scooter.local.enable {
    home.packages = [
      (scooter.lib.mkLocal {
        system = pkgs.stdenv.hostPlatform.system;
        module.scooter = {
          registryPrefix = "ghcr.io/dscrawford/scooter/";
          local.provider = "claude-code";
        };
      })
    ];
  };
}
