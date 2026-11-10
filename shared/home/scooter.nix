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
        Scooter UI origin. Behind oauth2-proxy: scooter-mode reads the
        `_oauth2_proxy` cookie from Firefox (or asks for it) and keeps it
        in auth-source.
      '';
    };
  };
}
