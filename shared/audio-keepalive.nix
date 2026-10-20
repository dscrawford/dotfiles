# shared/audio-keepalive.nix
# The amplifier on the analog output drops into signal-sense standby after a
# stretch of silence and takes seconds to wake, which eats the start of the
# next sound. The sink itself never suspends (hosts/local/audio.nix), so the
# fix lives in the signal: a 20 Hz tone at -40 dBFS is below hearing and
# below the sink's noise floor at normal volume, but above the amp's detector.
{ pkgs, ... }:

{
  systemd.user.services.audio-keepalive = {
    Unit = {
      Description = "Sub-audible tone keeping the amplifier out of standby";
      After = [ "pipewire-pulse.socket" ];
    };
    Service = {
      ExecStart = toString [
        "${pkgs.ffmpeg}/bin/ffmpeg -nostdin -loglevel error -re"
        "-f lavfi -i sine=frequency=20:sample_rate=48000"
        "-af volume=0.01"
        "-f pulse -name audio-keepalive -stream_name keepalive default"
      ];
      Restart = "always";
      RestartSec = 5;
    };
    Install.WantedBy = [ "default.target" ];
  };
}
