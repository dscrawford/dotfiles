# shared/home/scooter.nix
# Where the Scooter agent-shell bridge (pkgs/scooter-acp, wired in
# emacs/scooter.nix) points. Set url to "" to keep Scooter out of the agent picker.
{ lib, config, ... }:

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
        File holding the oauth2-proxy session cookie (`_oauth2_proxy=…`, or the
        bare value). Written by `M-x my/scooter-set-cookie`; the bridge rewrites
        it when oauth2-proxy refreshes the session.
      '';
    };
  };
}
