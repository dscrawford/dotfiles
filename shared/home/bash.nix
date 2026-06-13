# shared/home/bash.nix
# Bash configuration (bashrcExtra/initExtra). Secrets export lines come from
# the secrets module via the internal `my.secretExportLines` option.
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

      # Load secrets as environment variables (skip empty/unconfigured ones)
      ${secretExportLines}
    '' + ''

      # Set emacsclient socket name to match the current tmux pane's server
      if [ -n "$TMUX_PANE" ]; then
        export EMACS_SERVER="emacs-$(echo $TMUX_PANE | tr -d %)"
        export EDITOR="emacsclient -s $EMACS_SERVER"
      fi

      # Inside Emacs (eat), open files in a new Emacs window instead of nested instance
      if [ -n "$INSIDE_EMACS" ]; then
        emacs() {
          emacsclient -s "$EMACS_SERVER" -n --eval "(progn (split-window-right) (other-window 1) (find-file \"$(realpath "$1")\"))"
        }
      else
        alias emacs="emacs -nw"
      fi

      # Force xterm-256color for SSH (eat-truecolor rarely available on remote hosts)
      alias ssh='TERM=xterm-256color command ssh'

      # Eat shell integration (directory tracking, etc.)
      [ -n "$EAT_SHELL_INTEGRATION_DIR" ] && source "$EAT_SHELL_INTEGRATION_DIR/bash"
    '';
    initExtra = ''
      if command -v tmux &> /dev/null && [ -t 0 ] && [[ ! "$TERM" =~ screen ]] && [[ ! "$TERM" =~ tmux ]] && [ -z "$TMUX" ] && [ -z "$INSIDE_EMACS" ]; then
         exec tmux -f ${homeDir}/.config/tmux/tmux.conf
      fi

      # Hook direnv into interactive bash (disabled auto-integration to keep it after the interactive guard)
      eval "$(direnv hook bash)"
    '';
  };
}
