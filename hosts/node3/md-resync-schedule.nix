# hosts/node3/md-resync-schedule.nix
# md throttles a resync or reshape to sync_speed_min whenever the array sees
# other I/O, so the floor decides how much disk the reshape takes from
# Longhorn. High while nobody is using the cluster, low otherwise.
{ pkgs, ... }:

let
  zone = "America/Los_Angeles";
  nightFloor = 80000;
  dayFloor = 10000;
in
{
  systemd.services.md-resync-floor = {
    description = "Set md sync_speed_min for the time of day";
    after = [ "mdadm-assemble-data.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig.Type = "oneshot";
    path = [ pkgs.coreutils ];
    script = ''
      hour=$(TZ=${zone} date +%-H)
      if [ "$hour" -ge 23 ] || [ "$hour" -lt 8 ]; then floor=${toString nightFloor}; else floor=${toString dayFloor}; fi
      for f in /sys/block/md*/md/sync_speed_min; do
        [ -e "$f" ] && echo "$floor" > "$f" && echo "$f = $floor"
      done
    '';
  };

  systemd.timers.md-resync-floor = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = [ "*-*-* 23:00:00 ${zone}" "*-*-* 08:00:00 ${zone}" ];
      Persistent = true;
    };
  };
}
