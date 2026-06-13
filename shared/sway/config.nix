# shared/sway/config.nix
# Main Sway config string and the desktop home.packages list.
# Imported as a plain function returning { packages, swayConfig }.
# Script binary paths are passed in so the generated config is byte-identical.
{ pkgs, workspaceBin, wallpaperBin, lockBin, volumeBin, recordBin }:

{
  packages = with pkgs; [
    thunar
    tumbler      # Thumbnail service for Thunar (images, videos, PDFs)
    xdg-desktop-portal-gtk
    librepods    # AirPods controller (ANC/transparency, ear detection, battery); autostarted via `exec librepods` below
  ];

  swayConfig = ''
    # Sway config (migrated from i3)

    xwayland enable

    set $mod Mod4

    font pango:monospace 20

    # Include NixOS defaults (critical for xdg-desktop-portal/dbus/systemd integration)
    include /etc/sway/config.d/*
    exec dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP
    exec mako
    exec blueman-applet
    # LibrePods AirPods tray controller (left-click battery, right-click noise-control)
    exec librepods

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
