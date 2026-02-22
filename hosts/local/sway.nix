# hosts/local/sway.nix
# Sway window manager configuration for Home Manager
# Migrated from ~/.config/i3/config
{ pkgs, ... }:

{
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

    # Monitor layout (managed by nwg-displays)
    include ~/.config/sway/outputs

    # Idle and lock
    exec swayidle -w \
      timeout 300 'swaylock -f' \
      timeout 600 'swaymsg "output * power off"' \
      resume 'swaymsg "output * power on"' \
      before-sleep 'swaylock -f'

    # Volume controls (wpctl/PipeWire)
    set $refresh_i3status killall -SIGUSR1 i3status
    bindsym XF86AudioRaiseVolume exec wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.05+
    bindsym XF86AudioLowerVolume exec wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.05-
    bindsym XF86AudioMute exec wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle && $refresh_i3status
    bindsym XF86AudioMicMute exec wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle && $refresh_i3status

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

    # Applications
    bindsym Control+Shift+Mod1+f exec firefox

    # Status bar
    bar {
        status_command i3status
    }
  '';
}
