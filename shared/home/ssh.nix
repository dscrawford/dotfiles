# shared/home/ssh.nix
# SSH configuration
{ ... }:

{
  # SSH — force xterm-256color since eat-truecolor is rarely available on remote hosts
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    settings."*" = {
      SetEnv.TERM = "xterm-256color";
    };
    # GitHub over SSH; this is the key registered as dscrawford.
    settings."github.com" = {
      User = "git";
      IdentityFile = "~/.ssh/id_rsa_bitwarden";
      IdentitiesOnly = true;
    };
  };
}
