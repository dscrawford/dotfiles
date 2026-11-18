# The Scooter server scooter-mode (wired in emacs/scooter.nix) talks to.
# Set url to "" to keep Scooter out of Emacs and the agent picker.
# local.enable adds scooter-local, which runs one on this machine.
{ config, lib, pkgs, scooter, ... }:

let
  cfg = config.my.scooter;
  gh = cfg.local.github;
in
{
  options.my.scooter = {
    local.enable = lib.mkEnableOption "scooter-local: Scooter in a k3d cluster on this machine (needs Docker)";
    local.github = {
      enable = lib.mkEnableOption "GitHub in scooter-local sessions, as a GitHub App installed on the repos they work on";
      appId = lib.mkOption {
        type = lib.types.str;
        example = "123456";
        description = "The GitHub App's ID.";
      };
      installationId = lib.mkOption {
        type = lib.types.str;
        default = "";
        example = "12345678";
        description = "The App's installation to mint tokens from. Empty uses the first of owners.";
      };
      owners = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [ "my-user" "my-org" ];
        description = "The accounts whose installations the App may use; empty means any.";
      };
      host = lib.mkOption {
        type = lib.types.str;
        default = "github.com";
        description = "github.com, or a GitHub Enterprise Server hostname.";
      };
      privateKeyFile = lib.mkOption {
        type = lib.types.strMatching "/.+";
        example = "/run/user/1000/secrets/github-app-key.pem";
        description = ''
          The App's private key (PEM), read by `scooter-local up`, so it never
          enters the Nix store. A sops-nix secret's path works.
        '';
      };
    };
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
  config = lib.mkIf cfg.local.enable {
    home.packages = [
      (scooter.lib.mkLocal {
        system = pkgs.stdenv.hostPlatform.system;
        module = {
          scooter = {
            registryPrefix = "ghcr.io/dscrawford/scooter/";
            # optionalAttrs, not mkIf: a scooter without secretFiles must still evaluate.
            local = { provider = "claude-code"; } // lib.optionalAttrs gh.enable {
              secretFiles.github-app-key.private-key = gh.privateKeyFile;
            };
          };
          contribs = lib.optionalAttrs gh.enable { github = {
            enable = true;
            inherit (gh) appId installationId owners host;
            privateKeySecret = { name = "github-app-key"; key = "private-key"; };
            # Nothing reaches this machine from GitHub.
            webhooksEnabled = false;
          }; };
        };
      })
    ];
  };
}
