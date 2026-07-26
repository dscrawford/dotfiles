# PipeWire audio: Bluetooth codecs
{ config, lib, pkgs, ... }:

{
  security.rtkit.enable = true;

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
    wireplumber.extraConfig = {
      "10-bluez" = {
        "monitor.bluez.properties" = {
          "bluez5.enable-sbc-xq" = true;
          "bluez5.enable-msbc" = true;
          "bluez5.enable-hw-volume" = true;
          # A2DP only — prevents HFP profile switching that drops AirPods audio
          "bluez5.roles" = [ "a2dp_sink" "a2dp_source" ];
          # AAC re-enabled: its dropouts ("Missing completion reports") were
          # btusb USB autosuspend, fixed in boot.extraModprobeConfig.
          # Exclude LDAC (PipeWire 1.6.x decoder crash).
          "bluez5.codecs" = [ "sbc" "sbc_xq" "aac" "aptx" "aptx_hd" ];
        };
      };
      "11-bluetooth-policy" = {
        "wireplumber.settings" = {
          # Don't auto-switch from A2DP to HFP when a mic is opened
          "bluetooth.autoswitch-to-headset-profile" = false;
        };
      };
    };
  };
}
