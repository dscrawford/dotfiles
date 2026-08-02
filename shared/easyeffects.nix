# shared/easyeffects.nix
# EasyEffects input denoising for the desktop.
#
# Replaces the old system-level PipeWire filter-chain, which altered mic
# levels on sources other than the one it filtered. EasyEffects instead
# exposes a processed "EasyEffects Source" virtual mic and leaves other
# sources untouched.
#
# Chain: high-pass -> echo canceller -> DeepFilterNet -> soft gate.
#   - The high-pass drops desk-conducted key thump before the model sees it.
#   - The echo canceller (WebRTC AEC3) subtracts what the speakers are playing
#     so it doesn't feed back into the mic. It must run BEFORE DeepFilterNet:
#     AEC works by correlating the mic signal against a reference tap, and
#     DFN's non-linear processing destroys that correlation. Its own noise
#     suppression and AGC are off — DFN denoises far better, and AGC would
#     move mic levels, which is the behaviour we left the filter-chain over.
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
# Output passthrough: EasyEffects' processAllOutputs defaults to TRUE, so it
# moves every playback stream onto its virtual sink even with an empty output
# chain — three extra nodes (easyeffects_sink, ee_soe_output_level,
# ee_soe_spectrum) on the playback path, for no effects at all. Combined with
# DeepFilterNet's ~8ms compute block, that pushed the playback graph from 18us
# to 2.9ms of wait against a 5.33ms quantum and produced audible static
# (thousands of xruns on the ee_soe_* nodes). We only ever wanted mic
# processing, so outputs are switched off and inputs left on.
#
# Those two knobs live in EasyEffects' own KConfig INI, not in the presets, and
# not in dconf — 8.x moved from GTK/GSettings to Qt/KConfig, so any leftover
# ~/.config/dconf entries under com/github/wwmm/easyeffects are dead 7.x state.
# EasyEffects rewrites this file at runtime (window geometry, preset usage
# counts), so it cannot be a read-only home.file symlink; set just our keys on
# activation and leave the rest of the file alone.
#
# Autostarted from the sway config via exec (systemd user services on
# graphical-session.target never start under raw greetd).
{ pkgs, lib, ... }:

let
  micPreset = {
    input = {
      blocklist = [ ];
      plugins_order = [ "filter#0" "echo_canceller#0" "deepfilternet#0" "gate#0" ];

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

      # Echo canceller. EasyEffects links the reference ("probe") straight from
      # the physical output device's monitor, not from its own virtual sink —
      # see stream_input_effects.cpp, which links DbStreamOutputs::outputDevice
      # to the plugin's probe ports. So this keeps working with the playback
      # passthrough set below, and useDefaultOutputDevice (default true) makes
      # the probe follow the active sink if you switch to headphones/Bluetooth.
      "echo_canceller#0" = {
        bypass = false;
        input-gain = 0.0;
        output-gain = 0.0;
        echo-canceller = {
          enable = true;
          # Full AEC3, not the cut-down AECM intended for embedded devices.
          mobile-mode = false;
          enforce-high-pass = true;
          automatic-gain-control = false;
        };
        # DeepFilterNet handles denoising; a second suppressor here would fight
        # it. Level is still serialized (enums save as their label string).
        noise-suppression = {
          enable = false;
          level = "Moderate";
        };
        high-pass = {
          enable = true;
          full-band = true;
        };
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

  # Process microphones, leave playback alone. See the header for why this is an
  # activation script rather than a managed file. kwriteconfig6 resolves the
  # relative --file against XDG_CONFIG_HOME and rewrites only the named key, so
  # EasyEffects' other state in this file survives.
  home.activation.easyeffectsPipelines =
    lib.hm.dag.entryAfter [ "writeBoundary" ] (
      let
        kwriteconfig = "${pkgs.kdePackages.kconfig}/bin/kwriteconfig6";
        setKey = key: value: ''
          run ${kwriteconfig} --file easyeffects/db/easyeffectsrc \
            --group EffectsPipelines --key ${key} ${value}
        '';
      in
      (setKey "processAllOutputs" "false") + (setKey "processAllInputs" "true")
    );
}
