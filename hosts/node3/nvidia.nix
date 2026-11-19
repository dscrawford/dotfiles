# NVIDIA GTX 1080 Ti — for GPU compute workloads in Kubernetes
{ config, lib, pkgs, ... }:
{
  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
    "nvidia-x11"
    "nvidia-settings"
    "nvidia-kernel-modules"
    "nvidia-container-toolkit"
  ];

  services.xserver.videoDrivers = [ "nvidia" ];

  hardware = {
    graphics = {
      enable = true;
      enable32Bit = true;
    };
    nvidia = {
      modesetting.enable = true;
      open = false;  # GTX 1080 Ti is not supported by the open driver
      package = config.boot.kernelPackages.nvidiaPackages.legacy_580;
      # Without this, containers lose GPU access over time
      # (FFmpeg exit 187 / "Failed to initialize NVML").
      nvidiaPersistenced = true;
      powerManagement.enable = true;
    };
    # Generates CDI specs at /var/run/cdi/. Pair with generic-cdi-plugin, not
    # NVIDIA's k8s-device-plugin, which needs FHS paths and /etc/ld.so.cache.
    nvidia-container-toolkit = {
      enable = true;
      # The default profile mounts /run/opengl-driver and the driver package,
      # but the libnvidia-egl-* links there go through the module's
      # nvidia-egl-external-platforms symlinkJoin and then into egl-gbm /
      # egl-x11 / egl-wayland*. Neither hop is mounted, so inside a container
      # Xwayland's glamor cannot dlopen libnvidia-egl-gbm and silently falls
      # back to llvmpipe. containerPath ==
      # hostPath because the links are absolute store paths.
      mounts =
        let
          eglPlatforms = lib.findFirst
            (p: lib.hasPrefix "nvidia-egl-external-platforms" (lib.getName p))
            (throw "nvidia-egl-external-platforms not in hardware.graphics.extraPackages")
            config.hardware.graphics.extraPackages;
          same = path: { hostPath = path; containerPath = path; };
        in
        map same [
          "${eglPlatforms}"
          "${pkgs.egl-gbm}/lib"
          "${pkgs.egl-x11}/lib"
          "${pkgs.egl-wayland}/lib"
          "${pkgs.egl-wayland2}/lib"
        ];
    };
  };

  # nvidia-ctk mounts each driver .so at its store path, and the module also
  # mounts the whole driver package there, so the file mounts sit on top of the
  # directory mount. In a hostUsers: false pod crun builds that directory mount
  # as an idmapped clone that still shares propagation with the host's
  # /nix/store, so every file mount stacked on it lands on node3 too, and the
  # next GPU pod fails with `mount_setattr ... Operation not permitted`. The
  # directory already provides those files at the same paths, so drop them.
  systemd.services.nvidia-container-toolkit-cdi-generator.serviceConfig.ExecStartPost =
    let
      filter = pkgs.writeText "cdi-drop-nested-mounts.jq" ''
        if .containerEdits.mounts then
          [.containerEdits.mounts[] | select(.hostPath == .containerPath) | .containerPath] as $dirs
          | .containerEdits.mounts |= map(select(
              . as $x
              | ($x.hostPath == $x.containerPath)
                and any($dirs[]; . as $d | $x.containerPath | startswith($d + "/"))
              | not))
        else . end
      '';
    in
    pkgs.writeShellScript "cdi-drop-nested-mounts" ''
      spec="$RUNTIME_DIRECTORY/nvidia-container-toolkit.json"
      ${lib.getExe pkgs.jq} -f ${filter} "$spec" > "$spec.tmp"
      mv "$spec.tmp" "$spec"
    '';

  virtualisation.docker.enable = true;

  # So kubelet can schedule GPU pods.
  virtualisation.containerd.settings.plugins."io.containerd.grpc.v1.cri" = {
    enable_cdi = lib.mkForce true;
    cdi_spec_dirs = lib.mkForce [ "/var/run/cdi" "/etc/cdi" ];
  };

  # Jellyfin subtitle burn-in: hostPath-mounted into the pod at /usr/share/fonts,
  # with Dashboard > Playback > Fallback Font set to /usr/share/fonts/custom/.
  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-cjk-sans
  ];
}
