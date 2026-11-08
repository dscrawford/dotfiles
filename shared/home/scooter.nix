# shared/home/scooter.nix
# Where the Scooter agent-shell bridge (pkgs/scooter-acp, wired in
# emacs/scooter.nix) and the scooter-ssh command point. Set url to "" to keep
# Scooter out of the agent picker.
{ lib, config, pkgs, ... }:

let
  cfg = config.my.scooter;
  bridge = pkgs.callPackage ../../pkgs/scooter-acp { };
in
{
  options.my.scooter = {
    url = lib.mkOption {
      type = lib.types.str;
      default = "https://scooter.dcraw.net";
      example = "https://scooter.example.com";
      description = "Scooter UI origin; the bridge calls its /conversations and /agui API.";
    };

    cookieFile = lib.mkOption {
      type = lib.types.str;
      default = "${config.xdg.configHome}/scooter/cookie";
      description = ''
        File holding the oauth2-proxy session cookie (`name=value`). Written by
        `M-x my/scooter-login`, which runs when a session starts without a
        working cookie: through your Firefox profile when Firefox is the default
        browser, else a Chromium profile kept beside this file. The bridge
        rewrites it when oauth2-proxy refreshes the session.
      '';
    };
  };

  config = lib.mkIf (cfg.url != "") {
    home.packages = [
      (pkgs.writeShellScriptBin "scooter-ssh" ''
        export SCOOTER_URL="''${SCOOTER_URL:-${cfg.url}}"
        export SCOOTER_COOKIE_FILE="''${SCOOTER_COOKIE_FILE:-${cfg.cookieFile}}"
        exec ${bridge}/bin/scooter-ssh "$@"
      '')
    ];
  };
}
