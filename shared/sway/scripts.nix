# shared/sway/scripts.nix
# Sway helper scripts (writeShellApplication derivations).
# Imported as a plain function returning an attrset of script derivations.
{ pkgs }:

{
  workspace-script = pkgs.writeShellApplication {
    name = "workspace.sh";
    runtimeInputs = [ pkgs.sway pkgs.jq ];
    text = ''
      PREFIXES=(A B C D E F G H I J)

      # Get sorted list of active outputs
      mapfile -t OUTPUTS < <(swaymsg -t get_outputs | jq -r '.[] | select(.active) | .name' | sort)

      case "$1" in
        switch|move)
          FOCUSED=$(swaymsg -t get_outputs | jq -r '.[] | select(.focused) | .name')
          # Map focused output to its prefix
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
          # Focus the Nth output (1-indexed)
          IDX=$(($2 - 1))
          if [ "$IDX" -lt ''${#OUTPUTS[@]} ]; then
            swaymsg focus output "''${OUTPUTS[$IDX]}"
          fi
          ;;
        move-to)
          # Move container to the Nth output (1-indexed)
          IDX=$(($2 - 1))
          if [ "$IDX" -lt ''${#OUTPUTS[@]} ]; then
            swaymsg move container to output "''${OUTPUTS[$IDX]}"
          fi
          ;;
        init)
          # Bind all workspaces to their outputs and switch each to X01
          for i in "''${!OUTPUTS[@]}"; do
            P="''${PREFIXES[$i]}"
            O="''${OUTPUTS[$i]}"
            for W in $(seq 1 10); do
              swaymsg workspace "''${P}$(printf '%02d' "$W")" output "$O"
            done
            swaymsg workspace "''${P}01"
          done
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
