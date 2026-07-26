# shared/easyeffects.nix
# EasyEffects input denoising (RNNoise) for the desktop.
# Replaces the old system-level PipeWire filter-chain, which altered mic
# levels on sources other than the one it filtered. EasyEffects instead
# exposes a processed "EasyEffects Source" virtual mic and leaves other
# sources untouched.
#
# Autostarted from the sway config via exec (systemd user services on
# graphical-session.target never start under raw greetd).
{ pkgs, ... }:

let
  # Matches the old filter-chain behavior: RNNoise with 50% VAD threshold
  rnnoisePreset = {
    input = {
      blocklist = [ ];
      plugins_order = [ "rnnoise#0" ];
      "rnnoise#0" = {
        bypass = false;
        enable-vad = true;
        input-gain = 0.0;
        model-name = "";
        output-gain = 0.0;
        release = 20.0;
        vad-thres = 50.0;
        wet = 0.0;
      };
    };
  };

  snowballDevice = "alsa_input.usb-BLUE_MICROPHONE_Blue_Snowball_SUGA_2021_10_07_90385-00.mono-fallback";
  snowballProfile = "mono-fallback";
in
{
  home.packages = [ pkgs.easyeffects ];

  home.file.".config/easyeffects/input/rnnoise.json".text =
    builtins.toJSON rnnoisePreset;

  # Auto-apply the rnnoise preset whenever the Blue Snowball is the input
  home.file.".config/easyeffects/autoload/input/${snowballDevice}:${snowballProfile}.json".text =
    builtins.toJSON {
      device = snowballDevice;
      device-description = "Blue Snowball Mono";
      device-profile = snowballProfile;
      preset-name = "rnnoise";
    };
}
