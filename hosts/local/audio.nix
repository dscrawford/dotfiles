# PipeWire audio: Bluetooth codecs and RNNoise input denoising filter-chain
{ config, lib, pkgs, ... }:

{
  security.rtkit.enable = true;

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
    # PipeWire 1.6.x requires LADSPA_PATH for filter-chain plugin loading
    extraLadspaPackages = [ pkgs.rnnoise-plugin ];
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
    extraConfig.pipewire = {
      "99-input-denoising" = {
        "context.modules" = [
          {
            name = "libpipewire-module-filter-chain";
            args = {
              "node.description" = "Noise Canceling source";
              "media.name" = "Noise Canceling source";
              "filter.graph" = {
                nodes = [
                  {
                    type = "ladspa";
                    name = "rnnoise";
                    plugin = "librnnoise_ladspa"; # PipeWire 1.6.x appends .so automatically
                    label = "noise_suppressor_mono";
                    control = {
                      "VAD Threshold (%)" = 50.0;
                      "VAD Grace Period (ms)" = 200;
                      "Retroactive VAD Grace (ms)" = 0;
                    };
                  }
                ];
              };
              "capture.props" = {
                "node.name" = "capture.rnnoise_source";
                "node.passive" = true;
                "audio.rate" = 48000;
              };
              "playback.props" = {
                "node.name" = "rnnoise_source";
                "media.class" = "Audio/Source";
                "audio.rate" = 48000;
              };
            };
          }
        ];
      };
    };
  };
}
