# The Scooter server scooter-mode (wired in emacs/scooter.nix) talks to.
# Set url to "" to keep Scooter out of Emacs and the agent picker.
# local.enable adds scooter-local, which runs one on this machine.
{ config, lib, pkgs, scooter, username, enableSecrets ? false, ... }:

let
  cfg = config.my.scooter;
  homeDir = if pkgs.stdenv.hostPlatform.isDarwin then "/Users/${username}" else "/home/${username}";
in
{
  options.my.scooter = {
    local.enable = lib.mkEnableOption "scooter-local: Scooter in a k3d cluster on this machine (needs Docker)";
    local.github.enable = lib.mkEnableOption ''
      GitHub in scooter-local sessions, as the ScooterDcraw App. Its PEM is
      github_app_private_key in secrets/scooter-local.yaml'';
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

  config = lib.mkIf cfg.local.enable (lib.mkMerge ([
    {
      assertions = [{
        assertion = cfg.local.github.enable -> enableSecrets;
        message = "my.scooter.local.github needs enableSecrets (its App key comes from sops)";
      }];
      # The fork's images: its CI publishes every tag its main renders to its own
      # ghcr, while the default prefix (chadac-me) lacks the ones the fork changed.
      home.packages = [
        (scooter.lib.mkLocal {
          system = pkgs.stdenv.hostPlatform.system;
          module = {
            scooter = {
              registryPrefix = "ghcr.io/dscrawford/scooter/";
              local.provider = "claude-code";
              local.secretFiles = lib.mkIf cfg.local.github.enable {
                github-app-key.private-key = config.sops.secrets.scooter-github-app-key.path;
              };
            };
            # The App and installation KubeServer's src/scooter/scooter.nix uses.
            contribs.github = lib.mkIf cfg.local.github.enable {
              enable = true;
              appId = "5546629";
              owners = [ "dscrawford" "chadac-me" ];
              installationId = "177008700";
              privateKeySecret = { name = "github-app-key"; key = "private-key"; };
              # Nothing reaches this machine from GitHub.
              webhooksEnabled = false;
            };
          };
        })
      ];
    }
  ] ++ lib.optionals enableSecrets [
    # optionals, not mkIf: without enableSecrets the sops options don't exist.
    (lib.mkIf cfg.local.github.enable {
      # Read from the submodule checkout at activation, not copied into the store.
      sops = {
        age.keyFile = "${homeDir}/.config/sops/age/keys.txt";
        validateSopsFiles = false;
        secrets.scooter-github-app-key = {
          sopsFile = "${homeDir}/.local/dotfiles/secrets/scooter-local.yaml";
          key = "github_app_private_key";
        };
      };
    })
  ]));
}
