# shared/home/scooter.nix
# The Scooter server scooter-mode (wired in emacs/scooter.nix) talks to.
# Set url to "" to keep Scooter out of Emacs and the agent picker.
{ lib, ... }:

{
  options.my.scooter = {
    url = lib.mkOption {
      type = lib.types.str;
      default = "https://scooter.dcraw.net";
      example = "https://scooter.example.com";
      description = ''
        Scooter UI origin. Behind oauth2-proxy: scooter-mode reads its
        session cookie (cookieName) from Firefox and keeps it in
        auth-source.
      '';
    };
    cookieName = lib.mkOption {
      type = lib.types.str;
      default = "__Host-scooter_oauth2";
      example = "_oauth2_proxy";
      description = ''
        oauth2-proxy's --cookie-name at url (KubeServer
        config/scooter/oauth2-proxy.yaml). scooter-mode looks for this
        cookie in Firefox and sends it.
      '';
    };
  };
}
