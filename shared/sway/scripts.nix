# shared/sway/scripts.nix
# Sway helper scripts; imported as a function returning an attrset of derivations.
{ pkgs }:

{
  workspace-script = pkgs.writeShellApplication {
    name = "workspace.sh";
    runtimeInputs = [ pkgs.sway pkgs.jq ];
    text = ''
      PREFIXES=(A B C D E F G H I J)

      mapfile -t OUTPUTS < <(swaymsg -t get_outputs | jq -r '.[] | select(.active) | .name' | sort)

      case "$1" in
        switch|move)
          FOCUSED=$(swaymsg -t get_outputs | jq -r '.[] | select(.focused) | .name')
          PREFIX="A"
          for i in "''${!OUTPUTS[@]}"; do
            if [ "''${OUTPUTS[$i]}" = "$FOCUSED" ]; then
              PREFIX="''${PREFIXES[$i]}"
              break
            fi
          done
          NUM=$(printf "%02d" "$2")
          if [ "$1" = "switch" ]; then
            swaymsg workspace "''${PREFIX}$NUM"
          else
            swaymsg move container to workspace "''${PREFIX}$NUM"
          fi
          ;;
        focus)
          IDX=$(($2 - 1))
          if [ "$IDX" -lt ''${#OUTPUTS[@]} ]; then
            swaymsg focus output "''${OUTPUTS[$IDX]}"
          fi
          ;;
        move-to)
          IDX=$(($2 - 1))
          if [ "$IDX" -lt ''${#OUTPUTS[@]} ]; then
            swaymsg move container to output "''${OUTPUTS[$IDX]}"
          fi
          ;;
        init)
          # Creation-time assignments. These only apply when a workspace is
          # first created, so they are not enough on their own.
          for i in "''${!OUTPUTS[@]}"; do
            P="''${PREFIXES[$i]}"
            O="''${OUTPUTS[$i]}"
            for W in $(seq 1 10); do
              swaymsg workspace "''${P}$(printf '%02d' "$W")" output "$O"
            done
          done

          # A workspace created before its monitor was up (or while the prefix
          # order was different) lands on the wrong output and stays there,
          # because the assignment above never relocates it. Move any strays
          # to where they belong.
          RESTORE=$(swaymsg -t get_workspaces | jq -r '.[] | select(.focused) | .name')
          EXISTING=$(swaymsg -t get_workspaces | jq -r '.[] | "\(.name) \(.output)"')
          for i in "''${!OUTPUTS[@]}"; do
            P="''${PREFIXES[$i]}"
            O="''${OUTPUTS[$i]}"
            while read -r NAME OUT; do
              case "$NAME" in "$P"[0-9][0-9]) ;; *) continue ;; esac
              if [ "$OUT" != "$O" ]; then
                swaymsg -- workspace --no-auto-back-and-forth "$NAME"
                swaymsg move workspace to output "$O"
              fi
            done <<< "$EXISTING"
          done

          # Land every output on its first workspace. This also evicts sway's
          # default "1" workspace, which is empty and destroyed once hidden.
          for i in "''${!OUTPUTS[@]}"; do
            swaymsg -- workspace --no-auto-back-and-forth "''${PREFIXES[$i]}01"
          done

          # Restore focus, but only to a managed workspace — restoring "1"
          # would recreate the workspace we just evicted.
          case "$RESTORE" in
            [A-J][0-9][0-9]) swaymsg -- workspace --no-auto-back-and-forth "$RESTORE" ;;
          esac
          ;;
      esac
    '';
  };

  wallpaper-script = pkgs.writeShellApplication {
    name = "wallpaper.sh";
    runtimeInputs = [ pkgs.sway pkgs.jq pkgs.findutils ];
    text = ''
      WALLPAPER_DIR="$HOME/.local/share/wallpapers"

      if [ ! -d "$WALLPAPER_DIR" ] || [ -z "$(ls -A "$WALLPAPER_DIR" 2>/dev/null)" ]; then
        exit 0
      fi

      for OUTPUT in $(swaymsg -t get_outputs | jq -r '.[] | select(.active) | .name'); do
        IMG=$(find "$WALLPAPER_DIR" -type f \( -name '*.jpg' -o -name '*.jpeg' -o -name '*.png' -o -name '*.webp' \) | shuf -n 1)
        if [ -n "$IMG" ]; then
          swaymsg "output $OUTPUT bg '$IMG' fill"
        fi
      done
    '';
  };

  lock-script = pkgs.writeShellApplication {
    name = "lock.sh";
    runtimeInputs = [ pkgs.swaylock pkgs.findutils ];
    text = ''
      WALLPAPER_DIR="$HOME/.local/share/wallpapers"
      IMG=$(find "$WALLPAPER_DIR" -type f \( -name '*.jpg' -o -name '*.jpeg' -o -name '*.png' -o -name '*.webp' \) 2>/dev/null | shuf -n 1)
      if [ -n "$IMG" ]; then
        swaylock -f -i "$IMG" -s fill
      else
        swaylock -f
      fi
    '';
  };

  volume-script = pkgs.writeShellApplication {
    name = "volume.sh";
    runtimeInputs = [ pkgs.wireplumber pkgs.libnotify pkgs.gawk ];
    text = ''
      case "$1" in
        up)       wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.05+ ;;
        down)     wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.05- ;;
        mute)     wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle ;;
        mic-mute) wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle ;;
      esac

      VOL_RAW=$(wpctl get-volume @DEFAULT_AUDIO_SINK@)
      VOL_PCT=$(echo "$VOL_RAW" | awk '{printf "%.0f", $2 * 100}')
      MUTED=$(echo "$VOL_RAW" | grep -c MUTED || true)

      if [ "$MUTED" -eq 1 ]; then
        notify-send -h string:x-canonical-private-synchronous:volume -h int:value:"$VOL_PCT" -t 1500 "Volume: Muted"
      else
        notify-send -h string:x-canonical-private-synchronous:volume -h int:value:"$VOL_PCT" -t 1500 "Volume: $VOL_PCT%"
      fi
    '';
  };

  record-script = pkgs.writeShellApplication {
    name = "record.sh";
    runtimeInputs = [ pkgs.sway pkgs.jq pkgs.wf-recorder pkgs.libnotify pkgs.procps ];
    text = ''
      RECORDINGS_DIR="$HOME/Videos/recordings"

      if pgrep -x wf-recorder > /dev/null; then
        pkill -INT -x wf-recorder
        notify-send -t 3000 "Recording stopped" "Saved to $RECORDINGS_DIR"
        exit 0
      fi

      OUTPUT=$(swaymsg -t get_outputs | jq -r '.[] | select(.focused) | .name')
      mkdir -p "$RECORDINGS_DIR"
      FILENAME="$RECORDINGS_DIR/recording-$(date +%Y-%m-%d_%H-%M-%S).mp4"
      wf-recorder -o "$OUTPUT" --audio -f "$FILENAME" &
      disown
      notify-send -t 3000 "Recording started" "Press Ctrl+Alt+Shift+R to stop"
    '';
  };
}
