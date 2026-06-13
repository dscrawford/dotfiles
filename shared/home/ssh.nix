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
  };
}
