# hosts/local/sway.nix
# Sway window manager configuration for Home Manager
# Migrated from ~/.config/i3/config
{ pkgs, ... }:

let
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

  workspaceBin = "${workspace-script}/bin/workspace.sh";
  wallpaperBin = "${wallpaper-script}/bin/wallpaper.sh";
  lockBin = "${lock-script}/bin/lock.sh";
  volumeBin = "${volume-script}/bin/volume.sh";
  recordBin = "${record-script}/bin/record.sh";
in
{
  home.packages = with pkgs; [
    thunar
    tumbler      # Thumbnail service for Thunar (images, videos, PDFs)
    xdg-desktop-portal-gtk
  ];

  home.file.".config/waybar/config".text = builtins.toJSON {
    layer = "top";
    position = "top";
    height = 30;
    modules-left = [ "sway/workspaces" "sway/mode" ];
    modules-center = [ "clock" ];
    modules-right = [ "pulseaudio" "custom/gpu" "cpu" "memory" "disk" "network" "tray" ];
    "sway/workspaces" = {
      disable-scroll = true;
      format = "{name}";
      alphabetical_sort = true;
    };
    clock = {
      format = "{:%a %b %d  %I:%M %p}";
      tooltip-format = "{:%Y-%m-%d %A}";
    };
    cpu = {
      format = "CPU {usage}%";
      interval = 5;
    };
    memory = {
      format = "MEM {percentage}%";
      interval = 5;
    };
    disk = {
      format = "DISK {percentage_used}%";
      path = "/";
      interval = 30;
    };
    network = {
      format-ethernet = "ETH {ipaddr}";
      format-wifi = "WIFI {signalStrength}%";
      format-disconnected = "DISCONNECTED";
      interval = 10;
    };
    pulseaudio = {
      format = "VOL {volume}%";
      format-muted = "MUTED";
      on-click = "pavucontrol";
    };
    "custom/gpu" = {
      exec = "nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null || echo N/A";
      format = "GPU {}%";
      interval = 5;
    };
    tray = {
      spacing = 8;
    };
  };

  home.file.".config/waybar/style.css".text = ''
    * {
      font-family: monospace;
      font-size: 14px;
    }

    window#waybar {
      background-color: rgba(30, 30, 40, 0.9);
      color: #cccccc;
    }

    #workspaces button {
      padding: 0 8px;
      color: #888888;
      border-bottom: 2px solid transparent;
    }

    #workspaces button.focused {
      color: #ffffff;
      border-bottom: 2px solid #5294e2;
    }

    #workspaces button.urgent {
      color: #ff5555;
    }

    #clock, #cpu, #memory, #disk, #network, #pulseaudio, #tray {
      padding: 0 12px;
    }

    #pulseaudio {
      color: #8be9fd;
    }

    #custom-gpu {
      color: #ffb86c;
    }

    #cpu {
      color: #ff79c6;
    }

    #memory {
      color: #bd93f9;
    }

    #disk {
      color: #f1fa8c;
    }

    #network {
      color: #50fa7b;
    }

    #clock {
      color: #ffffff;
      font-weight: bold;
    }
  '';

  home.file.".config/mako/config".text = ''
    default-timeout=5000
  '';

  home.file.".config/xdg-desktop-portal-wlr/config".text = ''
    [screencast]
    max_fps=60
    chooser_type=simple
    chooser_cmd=slurp -f %o -or
  '';

  home.file.".config/sway/config".text = ''
    # Sway config (migrated from i3)

    xwayland enable

    set $mod Mod4

    font pango:monospace 20

    # Include NixOS defaults (critical for xdg-desktop-portal/dbus/systemd integration)
    include /etc/sway/config.d/*
    exec dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP
    exec mako
    exec blueman-applet

    # Monitor layout (managed by nwg-displays)
    include ~/.config/sway/outputs

    # Initialize workspaces on startup and when monitors change
    exec_always ${workspaceBin} init
    exec swaymsg -t subscribe -m '["output"]' | while read -r _; do sleep 1; ${workspaceBin} init; done

    # Randomized wallpaper (on startup and every 30 minutes)
    exec_always ${wallpaperBin}
    exec bash -c 'while true; do sleep 1800; ${wallpaperBin}; done'

    # Idle and lock
    exec_always pkill swayidle; swayidle -w \
      timeout 1800 '${lockBin}' \
      timeout 3600 'swaymsg "output * power off"' \
      resume 'swaymsg "output * power on"' \
      before-sleep '${lockBin}'

    # Volume controls (wpctl/PipeWire) with notifications
    set $refresh_i3status killall -SIGUSR1 i3status
    bindsym XF86AudioRaiseVolume exec ${volumeBin} up
    bindsym XF86AudioLowerVolume exec ${volumeBin} down
    bindsym XF86AudioMute exec ${volumeBin} mute
    bindsym XF86AudioMicMute exec ${volumeBin} mic-mute

    # Mouse+$mod to drag floating windows
    floating_modifier $mod


    # Terminal
    bindsym $mod+Shift+Return exec foot

    # Kill focused window
    bindsym $mod+Shift+c kill

    # Launcher
    bindsym $mod+p exec wmenu-run

    # Change focus
    bindsym $mod+j focus left
    bindsym $mod+k focus down
    bindsym $mod+l focus up
    bindsym $mod+semicolon focus right

    bindsym $mod+Left focus left
    bindsym $mod+Down focus down
    bindsym $mod+Up focus up
    bindsym $mod+Right focus right

    # Move focused window
    bindsym $mod+Shift+j move left
    bindsym $mod+Shift+k move down
    bindsym $mod+Shift+l move up
    bindsym $mod+Shift+semicolon move right

    bindsym $mod+Shift+Left move left
    bindsym $mod+Shift+Down move down
    bindsym $mod+Shift+Up move up
    bindsym $mod+Shift+Right move right

    # Split orientation
    bindsym $mod+h split h
    bindsym $mod+v split v

    # Toggle waybar visibility
    bindsym $mod+b bar mode toggle

    # Fullscreen
    bindsym $mod+f fullscreen toggle

    # Layout
    bindsym $mod+s layout stacking
    bindsym $mod+w layout tabbed
    bindsym $mod+e layout toggle split

    # Floating
    bindsym $mod+Shift+space floating toggle
    bindsym $mod+space focus mode_toggle

    # Focus parent
    bindsym $mod+a focus parent

    # Desktop switching (focus output/monitor)
    bindsym $mod+F1 exec ${workspaceBin} focus 1
    bindsym $mod+F2 exec ${workspaceBin} focus 2
    bindsym $mod+F3 exec ${workspaceBin} focus 3
    bindsym $mod+F4 exec ${workspaceBin} focus 4
    bindsym $mod+F5 exec ${workspaceBin} focus 5
    bindsym $mod+F6 exec ${workspaceBin} focus 6
    bindsym $mod+F7 exec ${workspaceBin} focus 7
    bindsym $mod+F8 exec ${workspaceBin} focus 8
    bindsym $mod+F9 exec ${workspaceBin} focus 9
    bindsym $mod+F10 exec ${workspaceBin} focus 10

    # Move focused window to another desktop
    bindsym $mod+Shift+F1 exec ${workspaceBin} move-to 1
    bindsym $mod+Shift+F2 exec ${workspaceBin} move-to 2
    bindsym $mod+Shift+F3 exec ${workspaceBin} move-to 3
    bindsym $mod+Shift+F4 exec ${workspaceBin} move-to 4
    bindsym $mod+Shift+F5 exec ${workspaceBin} move-to 5
    bindsym $mod+Shift+F6 exec ${workspaceBin} move-to 6
    bindsym $mod+Shift+F7 exec ${workspaceBin} move-to 7
    bindsym $mod+Shift+F8 exec ${workspaceBin} move-to 8
    bindsym $mod+Shift+F9 exec ${workspaceBin} move-to 9
    bindsym $mod+Shift+F10 exec ${workspaceBin} move-to 10

    # Switch workspace on focused desktop
    bindsym $mod+1 exec ${workspaceBin} switch 1
    bindsym $mod+2 exec ${workspaceBin} switch 2
    bindsym $mod+3 exec ${workspaceBin} switch 3
    bindsym $mod+4 exec ${workspaceBin} switch 4
    bindsym $mod+5 exec ${workspaceBin} switch 5
    bindsym $mod+6 exec ${workspaceBin} switch 6
    bindsym $mod+7 exec ${workspaceBin} switch 7
    bindsym $mod+8 exec ${workspaceBin} switch 8
    bindsym $mod+9 exec ${workspaceBin} switch 9
    bindsym $mod+0 exec ${workspaceBin} switch 10

    # Move window to workspace on focused desktop
    bindsym $mod+Shift+1 exec ${workspaceBin} move 1
    bindsym $mod+Shift+2 exec ${workspaceBin} move 2
    bindsym $mod+Shift+3 exec ${workspaceBin} move 3
    bindsym $mod+Shift+4 exec ${workspaceBin} move 4
    bindsym $mod+Shift+5 exec ${workspaceBin} move 5
    bindsym $mod+Shift+6 exec ${workspaceBin} move 6
    bindsym $mod+Shift+7 exec ${workspaceBin} move 7
    bindsym $mod+Shift+8 exec ${workspaceBin} move 8
    bindsym $mod+Shift+9 exec ${workspaceBin} move 9
    bindsym $mod+Shift+0 exec ${workspaceBin} move 10

    # Reload config
    bindsym $mod+Shift+slash reload

    # Exit Sway
    bindsym $mod+Shift+e exec swaynag -t warning -m 'Exit Sway? This will end your Wayland session.' -B 'Yes, exit' 'swaymsg exit'

    # Resize with Control+arrow
    bindsym $mod+Control+Left resize shrink width 1 px
    bindsym $mod+Control+Down resize grow height 1 px
    bindsym $mod+Control+Up resize shrink height 1 px
    bindsym $mod+Control+Right resize grow width 1 px

    # Screenshots
    bindsym Control+Shift+Mod1+s exec grim -g "$(slurp)" - | wl-copy

    # Screen recording toggle
    bindsym Control+Shift+Mod1+r exec ${recordBin}

    # Applications
    bindsym Control+Shift+Mod1+f exec firefox

    # Float popup/dialog windows automatically
    for_window [window_role="pop-up"] floating enable
    for_window [window_role="dialog"] floating enable
    for_window [window_role="task_dialog"] floating enable
    for_window [window_type="dialog"] floating enable
    for_window [window_type="menu"] floating enable
    for_window [window_type="splash"] floating enable
    for_window [window_type="tooltip"] floating enable
    for_window [window_type="utility"] floating enable

    # Status bar
    bar {
        swaybar_command waybar
    }
  '';
}
