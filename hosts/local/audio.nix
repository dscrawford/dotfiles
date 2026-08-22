# PipeWire audio: Bluetooth codecs, plus the graph tuning EasyEffects' echo
# canceller depends on (see shared/easyeffects.nix).
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
          # LDAC excluded: PipeWire 1.6.x decoder crash. AAC is fine — its
          # dropouts were btusb autosuspend, fixed in boot.extraModprobeConfig.
          "bluez5.codecs" = [ "sbc" "sbc_xq" "aac" "aptx" "aptx_hd" ];
        };
      };
      "11-bluetooth-policy" = {
        "wireplumber.settings" = {
          # Don't auto-switch from A2DP to HFP when a mic is opened
          "bluetooth.autoswitch-to-headset-profile" = false;
        };
      };
      # EasyEffects' AEC tracks mic-to-reference delay against the default
      # sink's monitor; WebRTC re-converges slowly, so any discontinuous shift
      # in that delay leaves it locked to a stale one until EasyEffects
      # restarts. Matched by name, never ~alsa_input.*: suspend keeps an idle
      # capture PCM closed, and the webcam mic has no business staying open.
      "12-easyeffects-aec" = {
        "monitor.alsa.rules" = [
          {
            matches = [
              { "node.name" = "~alsa_output.*"; }
              { "node.name" = "~alsa_input.*BLUE_MICROPHONE.*"; }
            ];
            actions.update-props = {
              # Idle suspend is the "degrades over time" trigger: the suspended
              # sink stops feeding the monitor (EE gets silence), and resume
              # refills the ALSA buffer at a new delay.
              "session.suspend-timeout-seconds" = 0;
              # 0 headroom on this codec (the default) means any scheduling
              # hiccup underruns the sink, which shifts the delay the same way.
              "api.alsa.headroom" = 1024;
            };
          }
          {
            matches = [ { "node.name" = "~alsa_input.*BLUE_MICROPHONE.*"; } ];
            actions.update-props = {
              # The mic drives the capture graph (the probe link welds the sink
              # into it), so this pins the graph's quantum. Discord's request
              # rounds to 256 frames (5.3 ms), too tight for DFN/WebRTC's 10 ms
              # blocks; lock-quantum forces 512 instead of ceding to the lowest
              # requester. Still under PipeWire's 1024 default.
              "node.latency" = "512/48000";
              "node.lock-quantum" = true;
            };
          }
        ];
      };
    };
  };
}
