# shared/easyeffects.nix
# Mic denoising chain: high-pass -> echo canceller -> DeepFilterNet -> soft gate.
#
# AEC must stay BEFORE DeepFilterNet: it correlates the mic against a reference
# tap, and DFN's non-linear processing destroys that correlation.
# DFN, not RNNoise: only DFN removes a keystroke landing mid-word — RNNoise's
# one-gain-per-band design handles steady noise but not transients.
# Presets must live under ~/.local/share (EE 8.x AppDataLocation); writing the
# old ~/.config/easyeffects path makes EE's xdg_migration() trash these symlinks.
# Autostarted from the sway config via exec (systemd user services on
# graphical-session.target never start under raw greetd).
{ pkgs, lib, ... }:

let
  micPreset = {
    input = {
      blocklist = [ ];
      plugins_order = [ "filter#0" "echo_canceller#0" "deepfilternet#0" "gate#0" ];

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

      # The probe is tapped from the physical output device's monitor, not EE's
      # own virtual sink, so this survives processAllOutputs being off below.
      "echo_canceller#0" = {
        bypass = false;
        input-gain = 0.0;
        output-gain = 0.0;
        echo-canceller = {
          enable = true;
          mobile-mode = false;
          enforce-high-pass = true;
          automatic-gain-control = false;
        };
        # DFN does the denoising; a second suppressor here would fight it.
        noise-suppression = {
          enable = false;
          level = "Moderate";
        };
        high-pass = {
          enable = true;
          full-band = true;
        };
      };

      # attenuation-limit 80 is the top of upstream's "balanced" range; raise
      # toward 100 if keystrokes still get through.
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

      # Deliberately soft: a hard gate after the model clips word tails.
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

  # processAllOutputs defaults to true, which routes playback through EE's sink
  # and, with DFN's ~8ms block, produced thousands of xruns and audible static.
  # These knobs live in EE's KConfig INI (not the presets, not dconf), and EE
  # rewrites that file at runtime — so set only our keys instead of symlinking.
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
