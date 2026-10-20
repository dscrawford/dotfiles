# The amplifier on the analog output goes to signal-sense standby after
# silence; PipeWire's sink never suspends (hosts/local/audio.nix), so the
# signal itself has to carry a tone that is below hearing but above the
# amp's detector.
{ pkgs, ... }:

{
  systemd.user.services.audio-keepalive = {
    Unit = {
      Description = "Sub-audible tone keeping the amplifier out of standby";
      After = [ "pipewire-pulse.socket" ];
    };
    Service = {
      ExecStart = toString [
        "${pkgs.ffmpeg-full}/bin/ffmpeg -nostdin -loglevel error -re"
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
