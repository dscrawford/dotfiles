# shared/home/bash.nix
# Secret export lines come from secrets.nix via `my.secretExportLines`.
{ config, lib, pkgs, username, enableSecrets ? false, ... }:

let
  isDarwin = pkgs.stdenv.isDarwin;
  homeDir = if isDarwin then "/Users/${username}" else "/home/${username}";
  secretExportLines = config.my.secretExportLines;
in
{
  programs.bash = {
    enable = true;
    enableCompletion = true;
    bashrcExtra = ''
      PS1='\u:\W\$ '
      export EDITOR="emacs -nw"
    '' + lib.optionalString isDarwin ''
      export SHELL="/run/current-system/sw/bin/bash"
    '' + lib.optionalString enableSecrets ''

      ${secretExportLines}
    '' + ''

      # One Emacs server per tmux pane.
      if [ -n "$TMUX_PANE" ]; then
        export EMACS_SERVER="emacs-$(echo $TMUX_PANE | tr -d %)"
        export EDITOR="emacsclient -s $EMACS_SERVER"
      fi

      # Inside eat, open files in a new window instead of a nested instance.
      if [ -n "$INSIDE_EMACS" ]; then
        emacs() {
          emacsclient -s "$EMACS_SERVER" -n --eval "(progn (split-window-right) (other-window 1) (find-file \"$(realpath "$1")\"))"
        }
      else
        alias emacs="emacs -nw"
      fi

      # eat-truecolor is rarely available on remote hosts.
      alias ssh='TERM=xterm-256color command ssh'

      [ -n "$EAT_SHELL_INTEGRATION_DIR" ] && source "$EAT_SHELL_INTEGRATION_DIR/bash"
    '';
    initExtra = ''
      if command -v tmux &> /dev/null && [ -t 0 ] && [[ ! "$TERM" =~ screen ]] && [[ ! "$TERM" =~ tmux ]] && [ -z "$TMUX" ] && [ -z "$INSIDE_EMACS" ]; then
         exec tmux -f ${homeDir}/.config/tmux/tmux.conf
      fi

      # Hooked manually so it lands after the interactive/tmux guard above.
      eval "$(direnv hook bash)"
    '';
  };
}
