# Desktop configuration for local machine
{ config, lib, pkgs, ... }:

{
  # === Boot ===
  boot = {
    loader = {
      efi = {
        canTouchEfiVariables = true;
        efiSysMountPoint = "/boot";
      };
      grub = {
        enable = true;
        device = "nodev";
        useOSProber = true;
        efiSupport = true;
        gfxmodeEfi = "1280x720";
      };
    };
    supportedFilesystems = [ "ntfs" ];
    kernelModules = [ "uinput" "v4l2loopback" ];
    extraModulePackages = [ config.boot.kernelPackages.v4l2loopback ];
    extraModprobeConfig = ''
      options v4l2loopback devices=1 video_nr=10 card_label="OBS-VirtualCam" exclusive_caps=1
    '';
  };

  # === Locale ===
  time.timeZone = "America/Los_Angeles";
  time.hardwareClockInLocalTime = true;
  i18n.defaultLocale = "en_US.UTF-8";
  console = {
    font = "Lat2-Terminus16";
    keyMap = "us";
  };

  # === Nixpkgs ===
  nixpkgs.config.allowUnfree = true;

  # === Hardware ===
  hardware = {
    graphics = {
      enable = true;
      enable32Bit = true;
      extraPackages = with pkgs; [
        nvidia-vaapi-driver
      ];
    };
    nvidia = {
      modesetting.enable = true;
      powerManagement.enable = false;
      open = false;      
      nvidiaSettings = true;
      package = config.boot.kernelPackages.nvidiaPackages.mkDriver {
        version = "610.43.02";
        sha256_64bit = "sha256-MDSgVLtM33dS/43CclZMsQVROAS/9TU4lFkBsWyndGM=";
        sha256_aarch64 = lib.fakeSha256;
        openSha256 = lib.fakeSha256;
        settingsSha256 = "sha256-0YAhufRgjDW+uR+kjaTb154fibpcDw8QowfrucoZsKE=";
        persistencedSha256 = lib.fakeSha256;
      };
    };
    bluetooth = {
      enable = true;
      powerOnBoot = true;
      settings = {
        General = {
          Enable = "Source,Sink,Media";
          Disable = "Socket";
          FastConnectable = true;
          Experimental = true;
        };
        Policy = {
          # Stop bluez retrying HFP connections every 60s when AirPods are in case
          # ("Unable to get Hands-Free Voice gateway SDP record: Host is down" spam)
          # Trade-off: no auto-reconnect; put AirPods in, then connect manually
          ReconnectAttempts = 0;
        };
      };
    };
    xpadneo.enable = true;
  };

  # === Display ===
  programs.sway = {
    enable = true;
    wrapperFeatures.gtk = true;
    extraPackages = with pkgs; [
      swaylock       # screen locker (replaces i3lock)
      swayidle       # idle management
      wmenu          # Wayland-native launcher (replaces dmenu)
      waybar         # status bar
      foot           # Wayland-native terminal
      nwg-displays   # GUI monitor configuration
      wl-clipboard   # Wayland clipboard (replaces xclip)
      slurp          # Region/output selector for screen sharing
      grim           # Screenshot tool for Wayland
      wf-recorder    # Screen recording for Wayland
      mako           # Notification daemon for Wayland
      libnotify      # notify-send command
    ];
  };

  # === Audio ===
  security.rtkit.enable = true;

  # === Services ===
  services = {
    xserver.videoDrivers = [ "nvidia" ];
    greetd = {
      enable = true;
      settings.default_session.command = "${pkgs.tuigreet}/bin/tuigreet --time --cmd 'sway --unsupported-gpu'";
    };
    pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      jack.enable = true;
      # PipeWire 1.6.x requires LADSPA_PATH for filter-chain plugin loading
      extraLadspaPackages = [ pkgs.rnnoise-plugin ];
      wireplumber.extraConfig = {
        "10-bluez" = {
          "monitor.bluez.properties" = {
            "bluez5.enable-sbc-xq" = true;
            "bluez5.enable-msbc" = true;
            "bluez5.enable-hw-volume" = true;
            # A2DP only — prevents HFP profile switching that drops AirPods audio
            "bluez5.roles" = [ "a2dp_sink" "a2dp_source" ];
            # Exclude AAC: on AirPods it causes packet dropouts/popping
            # ("Missing completion reports ... firmware bug?"). SBC-XQ is
            # lighter, near-identical quality, and stable. AirPods only do
            # AAC/SBC, so dropping AAC forces SBC-XQ.
            # Exclude LDAC (PipeWire 1.6.x decoder crash).
            "bluez5.codecs" = [ "sbc" "sbc_xq" "aptx" "aptx_hd" ];
          };
        };
        "11-bluetooth-policy" = {
          "wireplumber.settings" = {
            # Don't auto-switch from A2DP to HFP when a mic is opened
            "bluetooth.autoswitch-to-headset-profile" = false;
          };
        };
      };
      extraConfig.pipewire = {
        "99-input-denoising" = {
          "context.modules" = [
            {
              name = "libpipewire-module-filter-chain";
              args = {
                "node.description" = "Noise Canceling source";
                "media.name" = "Noise Canceling source";
                "filter.graph" = {
                  nodes = [
                    {
                      type = "ladspa";
                      name = "rnnoise";
                      plugin = "librnnoise_ladspa"; # PipeWire 1.6.x appends .so automatically
                      label = "noise_suppressor_mono";
                      control = {
                        "VAD Threshold (%)" = 50.0;
                        "VAD Grace Period (ms)" = 200;
                        "Retroactive VAD Grace (ms)" = 0;
                      };
                    }
                  ];
                };
                "capture.props" = {
                  "node.name" = "capture.rnnoise_source";
                  "node.passive" = true;
                  "audio.rate" = 48000;
                };
                "playback.props" = {
                  "node.name" = "rnnoise_source";
                  "media.class" = "Audio/Source";
                  "audio.rate" = 48000;
                };
              };
            }
          ];
        };
      };
    };
    dbus.enable = true;
    printing.enable = true;
    blueman.enable = true;
    flatpak.enable = true;
    gnome.gnome-keyring.enable = true;
    udev.extraRules = ''
      KERNEL=="uinput", SUBSYSTEM=="misc", MODE="0660", GROUP="input"
      KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="114d", ATTRS{idProduct}=="8a12", MODE="0660", TAG+="uaccess"
      KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="0bb4", ATTRS{idProduct}=="2c87", MODE="0660", TAG+="uaccess"
      KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="0bb4", ATTRS{idProduct}=="0306", MODE="0660", TAG+="uaccess"
      KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="0bb4", ATTRS{idProduct}=="0309", MODE="0660", TAG+="uaccess"
      KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="0bb4", ATTRS{idProduct}=="030a", MODE="0660", TAG+="uaccess"
      KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="0bb4", ATTRS{idProduct}=="030b", MODE="0660", TAG+="uaccess"
      KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="0bb4", ATTRS{idProduct}=="030c", MODE="0660", TAG+="uaccess"
      KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="0bb4", ATTRS{idProduct}=="030e", MODE="0660", TAG+="uaccess"
      KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="28de", ATTRS{idProduct}=="1043", MODE="0660", TAG+="uaccess"
      KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="28de", ATTRS{idProduct}=="1142", MODE="0660", TAG+="uaccess"
      KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="28de", ATTRS{idProduct}=="2000", MODE="0660", TAG+="uaccess"
      KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="28de", ATTRS{idProduct}=="2010", MODE="0660", TAG+="uaccess"
      KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="28de", ATTRS{idProduct}=="2011", MODE="0660", TAG+="uaccess"
      KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="28de", ATTRS{idProduct}=="2012", MODE="0660", TAG+="uaccess"
      KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="28de", ATTRS{idProduct}=="2021", MODE="0660", TAG+="uaccess"
      KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="28de", ATTRS{idProduct}=="2022", MODE="0660", TAG+="uaccess"
      KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="28de", ATTRS{idProduct}=="2050", MODE="0660", TAG+="uaccess"
      KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="28de", ATTRS{idProduct}=="2101", MODE="0660", TAG+="uaccess"
      KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="28de", ATTRS{idProduct}=="2102", MODE="0660", TAG+="uaccess"
      KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="28de", ATTRS{idProduct}=="2150", MODE="0660", TAG+="uaccess"
      KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="28de", ATTRS{idProduct}=="2300", MODE="0660", TAG+="uaccess"
      KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="28de", ATTRS{idProduct}=="2301", MODE="0660", TAG+="uaccess"
      SUBSYSTEM=="tty", ATTRS{idVendor}=="28de", ATTRS{idProduct}=="2102", MODE="0660", TAG+="uaccess"
      # Disable the TP-Link UB500 Bluetooth dongle (Realtek RTL8761B, comes up
      # as hci1). Its firmware drops HCI packet-completion reports ("Missing
      # completion reports for packet ... firmware bug?"), which stalls AirPods
      # A2DP audio and makes it pop in and out. Deauthorizing the USB device
      # forces all Bluetooth onto the reliable onboard Intel adapter
      # (8087:0025, hci0). Re-pair the AirPods after rebuild.
      ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="2357", ATTR{idProduct}=="0604", ATTR{authorized}="0"
    '';
  };

  # === GPU Monitoring ===
  # Logs GPU state every 10s to help diagnose hard freezes (Xid 31/109 errors)
  systemd.services.gpu-monitor = {
    description = "NVIDIA GPU state logger";
    after = [ "multi-user.target" ];
    wantedBy = [ "multi-user.target" ];
    path = [ config.hardware.nvidia.package.bin ];
    serviceConfig = {
      Type = "simple";
      ExecStart = pkgs.writeShellScript "gpu-monitor" ''
        LOG_DIR=/var/log/gpu-monitor
        mkdir -p $LOG_DIR
        find $LOG_DIR -name "*.log" -mtime +7 -delete 2>/dev/null
        LOG_FILE="$LOG_DIR/$(date +%Y-%m-%d).log"
        while true; do
          nvidia-smi \
            --query-gpu=timestamp,temperature.gpu,power.draw,utilization.gpu,utilization.memory,memory.used,memory.total,clocks.gr,clocks.mem,pstate \
            --format=csv,noheader >> "$LOG_FILE" 2>&1
          sleep 10
        done
      '';
      Restart = "always";
      RestartSec = 5;
    };
  };

  # === XDG ===
  xdg.portal = {
    enable = true;
    # wlr.enable adds the unpatched package; our extraPortals provides the patched one
    # TODO: Remove patch once xdg-desktop-portal-wlr > 0.8.2 is released
    # PR: https://github.com/emersion/xdg-desktop-portal-wlr/pull/380
    extraPortals = lib.mkForce [
      (pkgs.xdg-desktop-portal-wlr.overrideAttrs (old: {
        patches = (old.patches or []) ++ [
          ../../patches/xdg-desktop-portal-wlr-fix-duplicate-frame.patch
        ];
      }))
    ];
    config = lib.mkForce {
      sway = {
        default = [ "wlr" ];
      };
    };
  };

  # === Programs ===
  programs = {
    dconf.enable = true;
    gamemode.enable = true;
    gamescope.enable = true;
    steam = {
      enable = true;
      gamescopeSession = {
        enable = true;
        args = [
          "--expose-wayland"
          "--force-grab-cursor"
        ];
      };
      package = pkgs.steam.override {
        extraPkgs = pkgs: with pkgs; [ gamemode gamescope ];
      };
      # CachyOS Proton, pinned to the 20260520 build (20260521 crashes with
      # NVIDIA 610.43.02). Select per-game in Steam → Properties → Compatibility.
      extraCompatPackages = [ (pkgs.callPackage ../../pkgs/proton-cachyos { }) ];
    };
  };

  # === Virtualization ===
  virtualisation.docker.enable = true;

  # === Environment ===
  environment = {
    systemPackages = with pkgs; [
      exfat
      bluez
      cudatoolkit
      gtk3
      (ffmpeg-full.override { withUnfree = true; withOpengl = true; })
      v4l-utils
      guvcview
      obs-studio
      gnome-keyring
      libsecret
      tree
      findutils
      gnugrep
      gnused
      gawk
      util-linux
      jq
      libva-utils
      # Upstream renamed "Jellyfin Media Player" -> "Jellyfin Desktop" (v2.0.0);
      # nixpkgs aliased jellyfin-media-player -> jellyfin-desktop on 2025-12-14.
      # Use the canonical name so we don't depend on the deprecated alias.
      jellyfin-desktop
      rnnoise-plugin
    ];
    variables = {
      GSETTINGS_SCHEMA_DIR = "${pkgs.gtk3}/share/gsettings-schemas/${pkgs.gtk3.name}/glib-2.0/schemas";
      XDG_CURRENT_DESKTOP = "sway";
      GTK_THEME = "Adwaita:dark";
      # NVIDIA Wayland workarounds
      WLR_NO_HARDWARE_CURSORS = "1";
      NIXOS_OZONE_WL = "1";       # Electron/Chromium apps use Wayland
      GBM_BACKEND = "nvidia-drm";
      __GLX_VENDOR_LIBRARY_NAME = "nvidia";
      NVD_BACKEND = "direct";             # nvidia-vaapi-driver direct backend
    };
    pathsToLink = [ "/libexec" ];
  };

  # === Security ===
  security.pam.services.login.enableGnomeKeyring = true;

  # === Users ===
  users.groups.bluetooth = {};
  users.users.daniel = {
    isNormalUser = true;
    extraGroups = [ "wheel" "docker" "bluetooth" "input" "video" ];
  };

  # === Networking ===
  networking.hosts = {
    "192.168.0.2" = [ "node1" "api.kube" ];
    "192.168.0.4" = [ "node2" ];
  };
}
