# hosts/local/sway.nix
# Sway window manager configuration for Home Manager
# Migrated from ~/.config/i3/config
{ pkgs, ... }:

{
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

    # Workspaces
    set $ws1 "1"
    set $ws2 "2"
    set $ws3 "3"
    set $ws4 "4"
    set $ws5 "5"
    set $ws6 "6"
    set $ws7 "7"
    set $ws8 "8"
    set $ws9 "9"
    set $ws10 "10"

    bindsym $mod+1 workspace number $ws1
    bindsym $mod+2 workspace number $ws2
    bindsym $mod+3 workspace number $ws3
    bindsym $mod+4 workspace number $ws4
    bindsym $mod+5 workspace number $ws5
    bindsym $mod+6 workspace number $ws6
    bindsym $mod+7 workspace number $ws7
    bindsym $mod+8 workspace number $ws8
    bindsym $mod+9 workspace number $ws9
    bindsym $mod+0 workspace number $ws10

    bindsym $mod+Shift+1 move container to workspace number $ws1
    bindsym $mod+Shift+2 move container to workspace number $ws2
    bindsym $mod+Shift+3 move container to workspace number $ws3
    bindsym $mod+Shift+4 move container to workspace number $ws4
    bindsym $mod+Shift+5 move container to workspace number $ws5
    bindsym $mod+Shift+6 move container to workspace number $ws6
    bindsym $mod+Shift+7 move container to workspace number $ws7
    bindsym $mod+Shift+8 move container to workspace number $ws8
    bindsym $mod+Shift+9 move container to workspace number $ws9
    bindsym $mod+Shift+0 move container to workspace number $ws10

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
