# GPU monitoring systemd service
# Logs GPU state every 10s to help diagnose hard freezes (Xid 31/109 errors)
{ config, lib, pkgs, ... }:

{
  systemd.services.gpu-monitor = {
    description = "NVIDIA GPU state logger";
    wantedBy = [ "multi-user.target" ];
    path = [ config.hardware.nvidia.package.bin ];
    serviceConfig = {
      DynamicUser = true;
      LogsDirectory = "gpu-monitor";
      ExecStart = pkgs.writeShellScript "gpu-monitor" ''
        cd "$LOGS_DIRECTORY" || exit 1
        while true; do
          find . -name "*.log" -mtime +7 -delete
          nvidia-smi \
            --query-gpu=timestamp,temperature.gpu,power.draw,utilization.gpu,utilization.memory,memory.used,memory.total,clocks.gr,clocks.mem,pstate \
            --format=csv,noheader >> "$(date +%Y-%m-%d).log" 2>&1
          sleep 10
        done
      '';
      Restart = "always";
      RestartSec = 5;
    };
  };
}
