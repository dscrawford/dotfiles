# shared/home/tmux.nix
# Tmux configuration
{ pkgs, ... }:

{
  programs.tmux = {
    enable = true;
    shell = "${pkgs.bash}/bin/bash";
    extraConfig = ''
      set -g default-terminal "screen-256color"
      set-option -g status-position top
      set-option -g default-shell "${pkgs.bash}/bin/bash"
      set-option -g default-command "${pkgs.bash}/bin/bash"
      set-option -g automatic-rename on
      set-option -g automatic-rename-format '#{b:pane_current_path}'
    '';
  };
}
