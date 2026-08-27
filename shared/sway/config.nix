# shared/sway/config.nix
# Main Sway config string and the desktop home.packages list.
# Imported as a plain function returning { packages, swayConfig }.
{ pkgs, lib, workspaceBin, wallpaperBin, lockBin, volumeBin, recordBin }:

let
  # keyOf maps 1-10 to a bindsym key; workspace 10 sits on the 0 key.
  bindGroup = keyOf: cmd:
    lib.concatMapStringsSep "\n"
      (n: "bindsym ${keyOf n} exec ${workspaceBin} ${cmd} ${toString n}")
      (lib.range 1 10);
  numKey = n: toString (lib.mod n 10);

  floatFor = attr: vals:
    lib.concatMapStringsSep "\n"
      (v: ''for_window [${attr}="${v}"] floating enable'') vals;
in
{
  packages = with pkgs; [
    thunar
    tumbler      # thumbnail service for Thunar
    xdg-desktop-portal-gtk
  ];

  swayConfig = ''
    xwayland enable

    set $mod Mod4

    font pango:monospace 20

    # Include NixOS defaults (critical for xdg-desktop-portal/dbus/systemd integration)
    include /etc/sway/config.d/*
    exec dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP
    exec mako
    exec blueman-applet
    exec easyeffects --hide-window
    exec easyeffects-watchdog

    # Monitor layout (managed by nwg-displays)
    include ~/.config/sway/outputs

    # Initialize workspaces on startup and when monitors change
    exec_always ${workspaceBin} init
    exec swaymsg -t subscribe -m '["output"]' | while read -r _; do sleep 1; ${workspaceBin} init; done

    exec_always ${wallpaperBin}
    exec bash -c 'while true; do sleep 1800; ${wallpaperBin}; done'

    exec_always pkill swayidle; swayidle -w \
      timeout 1800 '${lockBin}' \
      timeout 3600 'swaymsg "output * power off"' \
      resume 'swaymsg "output * power on"' \
      before-sleep '${lockBin}'

    set $refresh_i3status killall -SIGUSR1 i3status
    bindsym XF86AudioRaiseVolume exec ${volumeBin} up
    bindsym XF86AudioLowerVolume exec ${volumeBin} down
    bindsym XF86AudioMute exec ${volumeBin} mute
    bindsym XF86AudioMicMute exec ${volumeBin} mic-mute

    floating_modifier $mod

    bindsym $mod+Shift+Return exec foot

    bindsym $mod+Shift+c kill

    bindsym $mod+p exec wmenu-run

    bindsym $mod+j focus left
    bindsym $mod+k focus down
    bindsym $mod+l focus up
    bindsym $mod+semicolon focus right

    bindsym $mod+Left focus left
    bindsym $mod+Down focus down
    bindsym $mod+Up focus up
    bindsym $mod+Right focus right

    bindsym $mod+Shift+j move left
    bindsym $mod+Shift+k move down
    bindsym $mod+Shift+l move up
    bindsym $mod+Shift+semicolon move right

    bindsym $mod+Shift+Left move left
    bindsym $mod+Shift+Down move down
    bindsym $mod+Shift+Up move up
    bindsym $mod+Shift+Right move right

    bindsym $mod+h split h
    bindsym $mod+v split v

    bindsym $mod+b bar mode toggle

    bindsym $mod+f fullscreen toggle

    bindsym $mod+s layout stacking
    bindsym $mod+w layout tabbed
    bindsym $mod+e layout toggle split

    bindsym $mod+Shift+space floating toggle
    bindsym $mod+space focus mode_toggle

    bindsym $mod+a focus parent

    # Desktop switching (focus output/monitor)
    ${bindGroup (n: "$mod+F${toString n}") "focus"}

    # Move focused window to another desktop
    ${bindGroup (n: "$mod+Shift+F${toString n}") "move-to"}

    # Switch workspace on focused desktop
    ${bindGroup (n: "$mod+${numKey n}") "switch"}

    # Move window to workspace on focused desktop
    ${bindGroup (n: "$mod+Shift+${numKey n}") "move"}

    bindsym $mod+Shift+slash reload

    bindsym $mod+Shift+e exec swaynag -t warning -m 'Exit Sway? This will end your Wayland session.' -B 'Yes, exit' 'swaymsg exit'

    bindsym $mod+Control+Left resize shrink width 1 px
    bindsym $mod+Control+Down resize grow height 1 px
    bindsym $mod+Control+Up resize shrink height 1 px
    bindsym $mod+Control+Right resize grow width 1 px

    bindsym Control+Shift+Mod1+s exec grim -g "$(slurp)" - | wl-copy

    bindsym Control+Shift+Mod1+r exec ${recordBin}

    bindsym Control+Shift+Mod1+f exec firefox

    bindsym Control+Shift+Mod1+e exec easyeffects-aec-reset

    # Size must match the anchor math in the waybar volume-dropdown script.
    for_window [app_id="com.saivert.pwvucontrol"] floating enable, resize set 520 400

    ${floatFor "window_role" [ "pop-up" "dialog" "task_dialog" ]}
    ${floatFor "window_type" [ "dialog" "menu" "splash" "tooltip" "utility" ]}

    bar {
        swaybar_command waybar
    }
  '';
}
