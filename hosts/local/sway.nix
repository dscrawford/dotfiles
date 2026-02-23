# hosts/local/sway.nix
# Sway window manager configuration for Home Manager
# Migrated from ~/.config/i3/config
{ pkgs, ... }:

{
  home.file.".local/bin/workspace.sh" = {
    executable = true;
    text = ''
      #!/bin/bash
      SWAYMSG=/run/current-system/sw/bin/swaymsg
      JQ=/run/current-system/sw/bin/jq

      OUTPUT=$($SWAYMSG -t get_outputs | $JQ -r '.[] | select(.focused) | .name')

      case "$OUTPUT" in
        DP-1) PREFIX="A" ;;
        DP-2) PREFIX="B" ;;
        DP-3) PREFIX="C" ;;
        *)    PREFIX="A" ;;
      esac

      case "$1" in
        switch) $SWAYMSG workspace "''${PREFIX}$2" ;;
        move)   $SWAYMSG move container to workspace "''${PREFIX}$2" ;;
      esac
    '';
  };

  home.file.".local/bin/volume.sh" = {
    executable = true;
    text = ''
      #!/bin/bash
      WPCTL=/run/current-system/sw/bin/wpctl
      NOTIFY=/run/current-system/sw/bin/notify-send

      case "$1" in
        up)       $WPCTL set-volume @DEFAULT_AUDIO_SINK@ 0.05+ ;;
        down)     $WPCTL set-volume @DEFAULT_AUDIO_SINK@ 0.05- ;;
        mute)     $WPCTL set-mute @DEFAULT_AUDIO_SINK@ toggle ;;
        mic-mute) $WPCTL set-mute @DEFAULT_AUDIO_SOURCE@ toggle ;;
      esac

      VOL_RAW=$($WPCTL get-volume @DEFAULT_AUDIO_SINK@)
      VOL_PCT=$(echo "$VOL_RAW" | awk '{printf "%.0f", $2 * 100}')
      MUTED=$(echo "$VOL_RAW" | grep -c MUTED)

      if [ "$MUTED" -eq 1 ]; then
        $NOTIFY -h string:x-canonical-private-synchronous:volume -h int:value:$VOL_PCT -t 1500 "Volume: Muted"
      else
        $NOTIFY -h string:x-canonical-private-synchronous:volume -h int:value:$VOL_PCT -t 1500 "Volume: $VOL_PCT%"
      fi
    '';
  };

  home.file.".config/waybar/config".text = builtins.toJSON {
    layer = "top";
    position = "top";
    height = 30;
    modules-left = [ "sway/workspaces" "sway/mode" ];
    modules-center = [ "clock" ];
    modules-right = [ "pulseaudio" "cpu" "memory" "disk" "network" "tray" ];
    "sway/workspaces" = {
      disable-scroll = true;
      format = "{name}";
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

    # Monitor layout (managed by nwg-displays)
    include ~/.config/sway/outputs

    # Idle and lock
    exec swayidle -w \
      timeout 300 'swaylock -f' \
      timeout 600 'swaymsg "output * power off"' \
      resume 'swaymsg "output * power on"' \
      before-sleep 'swaylock -f'

    # Volume controls (wpctl/PipeWire) with notifications
    set $refresh_i3status killall -SIGUSR1 i3status
    bindsym XF86AudioRaiseVolume exec ~/.local/bin/volume.sh up
    bindsym XF86AudioLowerVolume exec ~/.local/bin/volume.sh down
    bindsym XF86AudioMute exec ~/.local/bin/volume.sh mute
    bindsym XF86AudioMicMute exec ~/.local/bin/volume.sh mic-mute

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
    bindsym $mod+F1 focus output DP-1
    bindsym $mod+F2 focus output DP-2
    bindsym $mod+F3 focus output DP-3

    # Move focused window to another desktop
    bindsym $mod+Shift+F1 move container to output DP-1
    bindsym $mod+Shift+F2 move container to output DP-2
    bindsym $mod+Shift+F3 move container to output DP-3

    # Workspace assignments per output
    workspace A1 output DP-1
    workspace B1 output DP-2
    workspace C1 output DP-3

    # Switch workspace on focused desktop
    bindsym $mod+1 exec ~/.local/bin/workspace.sh switch 1
    bindsym $mod+2 exec ~/.local/bin/workspace.sh switch 2
    bindsym $mod+3 exec ~/.local/bin/workspace.sh switch 3
    bindsym $mod+4 exec ~/.local/bin/workspace.sh switch 4
    bindsym $mod+5 exec ~/.local/bin/workspace.sh switch 5
    bindsym $mod+6 exec ~/.local/bin/workspace.sh switch 6
    bindsym $mod+7 exec ~/.local/bin/workspace.sh switch 7
    bindsym $mod+8 exec ~/.local/bin/workspace.sh switch 8
    bindsym $mod+9 exec ~/.local/bin/workspace.sh switch 9
    bindsym $mod+0 exec ~/.local/bin/workspace.sh switch 10

    # Move window to workspace on focused desktop
    bindsym $mod+Shift+1 exec ~/.local/bin/workspace.sh move 1
    bindsym $mod+Shift+2 exec ~/.local/bin/workspace.sh move 2
    bindsym $mod+Shift+3 exec ~/.local/bin/workspace.sh move 3
    bindsym $mod+Shift+4 exec ~/.local/bin/workspace.sh move 4
    bindsym $mod+Shift+5 exec ~/.local/bin/workspace.sh move 5
    bindsym $mod+Shift+6 exec ~/.local/bin/workspace.sh move 6
    bindsym $mod+Shift+7 exec ~/.local/bin/workspace.sh move 7
    bindsym $mod+Shift+8 exec ~/.local/bin/workspace.sh move 8
    bindsym $mod+Shift+9 exec ~/.local/bin/workspace.sh move 9
    bindsym $mod+Shift+0 exec ~/.local/bin/workspace.sh move 10

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
