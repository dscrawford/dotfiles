# shared/sway/waybar.nix
# Waybar settings (pre-JSON attrset) and stylesheet.
# Imported as a plain function returning { settings, style }.
{ pkgs, ... }:

let
  inherit (pkgs) lib;

  # 11-step unicode load bar, used as format-icons so waybar picks the step
  # matching the percentage.
  barWidth = 10;
  bars = builtins.genList
    (i: lib.concatStrings (builtins.genList (_: "█") i)
      + lib.concatStrings (builtins.genList (_: "░") (barWidth - i)))
    (barWidth + 1);

  # Ordered pairs, not an attrset: keeps the stylesheet order stable.
  moduleColors = [
    [ "#pulseaudio" "#8be9fd" ]
    [ "#custom-gpu" "#ffb86c" ]
    [ "#cpu" "#ff79c6" ]
    [ "#memory" "#bd93f9" ]
    [ "#custom-disk" "#f1fa8c" ]
    [ "#network" "#50fa7b" ]
    [ "#battery" "#69ff94" ]
    [ "#battery.warning" "#ffb86c" ]
    [ "#battery.critical" "#ff5555" ]
  ];
  colorRules = lib.concatMapStringsSep "\n\n"
    (p: "${lib.elemAt p 0} {\n  color: ${lib.elemAt p 1};\n}")
    moduleColors;

  # custom modules lack format-icons support, so these emit JSON carrying a
  # percentage for {icon} substitution.
  disk-status = pkgs.writeShellScript "waybar-disk" ''
    pct=$(${pkgs.coreutils}/bin/df --output=pcent / | ${pkgs.gnused}/bin/sed -n '2s/[ %]//gp')
    used=$(${pkgs.coreutils}/bin/df -h --output=used,size / | ${pkgs.gnused}/bin/sed -n '2s/^ *//p' | ${pkgs.coreutils}/bin/tr -s ' ')
    echo "{\"percentage\": $pct, \"tooltip\": \"/ ''${used/ / of }\"}"
  '';

  # Toggles pwvucontrol anchored under the bar. Size must match the for_window
  # rule for com.saivert.pwvucontrol in sway/config.nix.
  volume-dropdown = pkgs.writeShellScript "waybar-volume-dropdown" ''
    app_id="com.saivert.pwvucontrol"
    has_window() {
      swaymsg -t get_tree | ${pkgs.jq}/bin/jq -e --arg a "$app_id" \
        '[recurse(.nodes[]?, .floating_nodes[]?) | select(.app_id? == $a)]
         | length > 0' >/dev/null
    }
    if has_window; then
      swaymsg "[app_id=$app_id] kill"
      exit 0
    fi
    ${pkgs.pwvucontrol}/bin/pwvucontrol &
    # The workspace it landed on, not the focused one — they differ on multi-monitor.
    for _ in $(seq 50); do
      ww=$(swaymsg -t get_tree | ${pkgs.jq}/bin/jq --arg a "$app_id" '
        [recurse(.nodes[]?) | select(.type? == "workspace")
         | select([recurse(.nodes[]?, .floating_nodes[]?)
                   | select(.app_id? == $a)] | length > 0)
        ][0].rect.width // empty')
      [ -n "$ww" ] && break
      sleep 0.1
    done
    [ -n "$ww" ] || exit 1
    # move position is workspace-relative and that rect already excludes the bar
    swaymsg "[app_id=$app_id] move position $((ww - 528)) 4"
  '';

  gpu-status = pkgs.writeShellScript "waybar-gpu" ''
    pct=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null)
    if [ -z "$pct" ]; then
      echo '{"text": "N/A", "percentage": 0}'
    else
      echo "{\"percentage\": $pct, \"tooltip\": \"GPU $pct%\"}"
    fi
  '';
in
{
  settings = {
    layer = "top";
    position = "top";
    height = 30;
    modules-left = [ "sway/workspaces" "sway/mode" ];
    modules-center = [ "clock" ];
    modules-right = [ "pulseaudio" "custom/gpu" "cpu" "memory" "custom/disk" "network" "battery" "tray" ];
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
      format = "CPU {icon}";
      format-icons = bars;
      tooltip = true;
      interval = 5;
    };
    memory = {
      format = "MEM {icon}";
      format-icons = bars;
      tooltip-format = "{used:0.1f}G / {total:0.1f}G ({percentage}%)";
      interval = 5;
    };
    "custom/disk" = {
      exec = disk-status;
      return-type = "json";
      format = "DISK {icon}";
      format-icons = bars;
      interval = 30;
    };
    network = {
      format-ethernet = "ETH {ipaddr}";
      format-wifi = "WIFI {icon}";
      format-icons = bars;
      tooltip-format-wifi = "{essid} {signalStrength}%";
      format-disconnected = "DISCONNECTED";
      interval = 10;
    };
    pulseaudio = {
      format = "VOL {icon}";
      format-muted = "MUTED";
      format-icons.default = bars;
      tooltip-format = "{desc} {volume}%";
      on-click = volume-dropdown;
    };
    # waybar skips this module at startup on machines without a battery.
    battery = {
      format = "BAT {icon}";
      format-charging = "CHR {icon}";
      format-icons = bars;
      tooltip-format = "{capacity}% — {timeTo}";
      states = {
        warning = 30;
        critical = 15;
      };
      interval = 30;
    };
    "custom/gpu" = {
      exec = gpu-status;
      return-type = "json";
      format = "GPU {icon}";
      format-icons = bars;
      interval = 5;
    };
    tray = {
      spacing = 8;
    };
  };

  style = ''
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

    #clock, #cpu, #memory, #custom-disk, #network, #pulseaudio, #battery, #tray {
      padding: 0 12px;
    }

    ${colorRules}

    #clock {
      color: #ffffff;
      font-weight: bold;
    }
  '';
}
