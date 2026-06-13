# GPU monitoring systemd service
# Logs GPU state every 10s to help diagnose hard freezes (Xid 31/109 errors)
{ config, lib, pkgs, ... }:

{
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
}
