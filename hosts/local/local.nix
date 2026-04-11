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
    kernelModules = [ "uinput" ];
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
  nixpkgs.config = {
    allowUnfree = true;
    allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
      "nvidia-x11"
      "nvidia-settings"
      "nvidia-persistenced"
      "steam-original"
      "steam-unwrapped"
    ];
  };

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
        version = "595.58.03";
        sha256_64bit = "sha256-jA1Plnt5MsSrVxQnKu6BAzkrCnAskq+lVRdtNiBYKfk=";
        sha256_aarch64 = lib.fakeSha256;
        openSha256 = "sha256-ZpuVZybW6CFN/gz9rx+UJvQ715FZnAOYfHn5jt5Z2C8=";
        settingsSha256 = "sha256-ZpuVZybW6CFN/gz9rx+UJvQ715FZnAOYfHn5jt5Z2C8=";
        persistencedSha256 = lib.fakeSha256;
      };
    };
    bluetooth = {
      enable = true;
      settings.General = {
        Enable = "Source,Sink,Media,Socket";
        Disable = "Socket";
      };
    };
    xpadneo.enable = true;
  };

  # === Display ===
  services.xserver.videoDrivers = [ "nvidia" ];
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
  services.greetd = {
    enable = true;
    settings.default_session.command = "${pkgs.tuigreet}/bin/tuigreet --time --cmd 'sway --unsupported-gpu'";
  };

  # === Audio ===
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };

  # === Services ===
  services = {
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
    wlr.enable = true;
    extraPortals = lib.mkForce [ pkgs.xdg-desktop-portal-wlr ];
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
      gamescopeSession.enable = true;
      package = pkgs.steam.override {
        extraPkgs = pkgs: with pkgs; [ gamemode gamescope ];
      };
    };
    alvr = {
      enable = true;
      openFirewall = true;
      package = pkgs.alvr;
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
      gnome-keyring
      libsecret
      tree
      findutils
      gnugrep
      gnused
      gawk
      util-linux
      jq
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
  users.users.daniel = {
    isNormalUser = true;
    extraGroups = [ "wheel" "docker" "bluetooth" "input" ];
  };

  # === Networking ===
  networking.hosts = {
    "192.168.0.2" = [ "node1" "api.kube" ];
    "192.168.0.4" = [ "node2" ];
  };
}
