# PipeWire audio: Bluetooth codecs, plus the graph tuning EasyEffects' echo
# canceller depends on (see shared/easyeffects.nix).
{ config, lib, pkgs, ... }:

{
  security.rtkit = {
    enable = true;
    # rtkit's defaults cap RT at priority 20 and SIGKILL a thread that spins
    # 200ms without blocking; a DeepFilterNet stall under a build hits both.
    args = [
      "--scheduling-policy=FIFO"
      "--our-realtime-priority=89"
      "--max-realtime-priority=88"
      "--min-nice-level=-19"
      "--rttime-usec-max=5000000"
    ];
  };

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
    # Robustness over latency (docs/audio-under-load-research.md): a 1024
    # floor gives the DeepFilterNet worker 21ms per cycle instead of 10, the
    # data loop lives on a reserved physical core (11/23, kept free of nix
    # builds in priority.nix). module-rt is not re-declared: pipewire.conf
    # already loads it asking for 88 (clients 83), which rtkit now grants, and
    # it sizes RLIMIT_RTTIME from rtkit's --rttime-usec-max.
    extraConfig = {
      pipewire."90-robust" = {
        "context.properties" = {
          "default.clock.rate" = 48000;
          "default.clock.quantum" = 1024;
          "default.clock.min-quantum" = 1024;
          "default.clock.max-quantum" = 2048;
        };
        "context.data-loops" = [
          {
            "loop.rt-prio" = -1;
            "loop.class" = [ "data.rt" ];
            "thread.name" = "data-loop.0";
            "thread.affinity" = [ 11 23 ];
          }
        ];
      };
      # Games and browsers talk PulseAudio and would otherwise pull the graph
      # down to 256-sample cycles.
      pipewire-pulse."92-pulse-floor" = {
        "pulse.properties" = {
          "pulse.min.quantum" = "1024/48000";
          "pulse.min.req" = "1024/48000";
        };
      };
    };
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
            # The capture graph must not run a shorter cycle than the graph
            # floor: 512 halved DeepFilterNet's time budget on the mic side.
            actions.update-props = {
              "node.latency" = "1024/48000";
            };
          }
        ];
      };
    };
  };
}
