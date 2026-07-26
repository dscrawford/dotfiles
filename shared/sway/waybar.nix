# shared/sway/waybar.nix
# Waybar settings (pre-JSON attrset) and stylesheet.
# Imported as a plain function returning { settings, style }.
{ pkgs, ... }:

let
  inherit (pkgs) lib;

  # 11-step unicode load bar: ░░░░░░░░░░ .. ██████████.
  # Used as format-icons so waybar picks the step matching the percentage.
  barWidth = 10;
  bars = builtins.genList
    (i: lib.concatStrings (builtins.genList (_: "█") i)
      + lib.concatStrings (builtins.genList (_: "░") (barWidth - i)))
    (barWidth + 1);

  # disk and the GPU exec lack format-icons support, so these scripts emit
  # JSON with a percentage for the custom module's {icon} substitution.
  disk-status = pkgs.writeShellScript "waybar-disk" ''
    pct=$(${pkgs.coreutils}/bin/df --output=pcent / | ${pkgs.gnused}/bin/sed -n '2s/[ %]//gp')
    used=$(${pkgs.coreutils}/bin/df -h --output=used,size / | ${pkgs.gnused}/bin/sed -n '2s/^ *//p' | ${pkgs.coreutils}/bin/tr -s ' ')
    echo "{\"percentage\": $pct, \"tooltip\": \"/ ''${used/ / of }\"}"
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
      on-click = "pwvucontrol";
    };
    # Only rendered on machines with a battery; waybar skips the module
    # at startup when none is present.
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

    #custom-disk {
      color: #f1fa8c;
    }

    #network {
      color: #50fa7b;
    }

    #battery {
      color: #69ff94;
    }

    #battery.warning {
      color: #ffb86c;
    }

    #battery.critical {
      color: #ff5555;
    }

    #clock {
      color: #ffffff;
      font-weight: bold;
    }
  '';
}
