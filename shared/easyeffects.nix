# shared/easyeffects.nix
# EasyEffects input denoising for the desktop.
#
# Replaces the old system-level PipeWire filter-chain, which altered mic
# levels on sources other than the one it filtered. EasyEffects instead
# exposes a processed "EasyEffects Source" virtual mic and leaves other
# sources untouched.
#
# Chain: high-pass -> DeepFilterNet -> soft gate.
#   - The high-pass drops desk-conducted key thump before the model sees it.
#   - DeepFilterNet ("Deep Noise Remover") is the only stage that can remove a
#     keystroke landing mid-word; RNNoise's one-gain-per-band design handles
#     steady noise but not transients. nixpkgs wraps easyeffects with
#     LADSPA_PATH pointing at deepfilternet, so the plugin is available.
#   - The gate is deliberately soft (-18 dB, slow release): it only acts
#     between phrases, and a hard gate after the model clips word tails.
#
# Paths: EasyEffects 8.x reads presets from AppDataLocation
# (~/.local/share/easyeffects), NOT AppConfigLocation. Writing to the old
# ~/.config/easyeffects path makes EE's xdg_migration() copy the files out and
# move the originals to the trash, which destroys these symlinks and silently
# decouples the config from what EE actually loads.
#
# Autostarted from the sway config via exec (systemd user services on
# graphical-session.target never start under raw greetd).
{ pkgs, ... }:

let
  micPreset = {
    input = {
      blocklist = [ ];
      plugins_order = [ "filter#0" "deepfilternet#0" "gate#0" ];

      # High-pass: remove low-frequency thump conducted through the desk.
      # Enum fields serialize as their label strings, not indices.
      "filter#0" = {
        bypass = false;
        input-gain = 0.0;
        output-gain = 0.0;
        type = "High-pass";
        mode = "RLC (BT)";
        equal-mode = "IIR";
        slope = "x2";
        frequency = 90.0;
        width = 4.0;
        quality = 0.0;
        gain = 0.0;
        balance = 0.0;
        decramp = "Off";
      };

      # DeepFilterNet. attenuation-limit 80 is the top of the range upstream
      # calls balanced; raise toward 100 if clicks still get through.
      # min-processing-threshold is the knob to A/B first — upstream docs
      # describe its direction ambiguously, so this leaves it at the default.
      "deepfilternet#0" = {
        bypass = false;
        input-gain = 0.0;
        output-gain = 0.0;
        attenuation-limit = 80.0;
        min-processing-threshold = -10.0;
        max-erb-processing-threshold = 30.0;
        max-df-processing-threshold = 20.0;
        min-processing-buffer = 0;
        post-filter-beta = 0.05;
      };

      # Soft gate, after the model. Hysteresis stops it chattering on clicks
      # sitting near the threshold.
      "gate#0" = {
        bypass = false;
        input-gain = 0.0;
        output-gain = 0.0;
        dry = -80.01;
        wet = 0.0;
        attack = 10.0;
        release = 250.0;
        curve-threshold = -40.0;
        curve-zone = -6.0;
        hysteresis = true;
        hysteresis-threshold = -6.0;
        hysteresis-zone = -3.0;
        reduction = -18.0;
        makeup = 0.0;
        hpf-mode = "Off";
        lpf-mode = "Off";
        sidechain = {
          type = "Internal";
          mode = "RMS";
          source = "Middle";
          preamp = 0.0;
          reactivity = 10.0;
          lookahead = 0.0;
        };
      };
    };
  };

  presetName = "mic-denoise";

  snowballDevice = "alsa_input.usb-BLUE_MICROPHONE_Blue_Snowball_SUGA_2021_10_07_90385-00.mono-fallback";
  snowballProfile = "mono-fallback";
in
{
  home.packages = [ pkgs.easyeffects ];

  home.file.".local/share/easyeffects/input/${presetName}.json" = {
    text = builtins.toJSON micPreset;
    force = true;
  };

  # Auto-apply the preset whenever the Blue Snowball is the input
  home.file.".local/share/easyeffects/autoload/input/${snowballDevice}:${snowballProfile}.json" = {
    text = builtins.toJSON {
      device = snowballDevice;
      device-description = "Blue Snowball Mono";
      device-profile = snowballProfile;
      preset-name = presetName;
    };
    force = true;
  };
}
