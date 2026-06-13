# shared/sway/waybar.nix
# Waybar settings (pre-JSON attrset) and stylesheet.
# Imported as a plain function returning { settings, style }.
{ ... }:

{
  settings = {
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
}
