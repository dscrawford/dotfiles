# Mic chain: high-pass -> RNNoise -> gate -> echo canceller.
#
# Canceller runs last, which is backwards: AEC correlates the mic against a
# reference tap and upstream denoising degrades that. Verified working anyway;
# if echo cancellation regresses, move echo_canceller#0 second.
# Presets must live under ~/.local/share — EE 8.x xdg_migration() trashes
# symlinks written to the old ~/.config/easyeffects path.
# easyeffects-watchdog is built here but not autostarted; see shared/sway/config.nix.
{ pkgs, lib, ... }:

let
  micPreset = {
    input = {
      blocklist = [ ];
      plugins_order = [ "filter#0" "rnnoise#0" "gate#0" "echo_canceller#0" ];

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
        # VeryHigh is index 3 of Low/Moderate/High/VeryHigh.
        noise-suppression = {
          enable = true;
          level = "VeryHigh";
        };
        high-pass = {
          enable = true;
          full-band = true;
        };
      };

      # Defaults spelled out so an EE update cannot silently retune the mic.
      "rnnoise#0" = {
        bypass = false;
        input-gain = 0.0;
        output-gain = 0.0;
        enable-vad = true;
        vad-thres = 50.0;
        release = 20.0;
        wet = 0.0;
        model-name = "";
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

  # Loading this is how the reset script gets rid of the echo canceller
  # instance; its only job is to have a different plugins_order.
  resetPresetName = "mic-denoise-aec-reset";
  resetPreset = {
    input = {
      blocklist = [ ];
      plugins_order = [ "filter#0" ];
      "filter#0" = micPreset.input."filter#0";
    };
  };

  snowballDevice = "alsa_input.usb-BLUE_MICROPHONE_Blue_Snowball_SUGA_2021_10_07_90385-00.mono-fallback";
  snowballProfile = "mono-fallback";

  # init_webrtc() runs on construction, so a stale delay estimate only clears
  # when the instance is rebuilt. A preset swap does that without dropping
  # easyeffects_source; try it before a full restart.
  aecReset = pkgs.writeShellApplication {
    name = "easyeffects-aec-reset";
    runtimeInputs = [
      pkgs.easyeffects
      pkgs.pipewire
      pkgs.jq
      pkgs.util-linux
      pkgs.procps
      pkgs.libnotify
      pkgs.coreutils
    ];
    text = ''
      QUIET=0
      if [ "''${1:-}" = "--quiet" ]; then QUIET=1; fi

      # Interleaved runs can land the reset preset last, silently leaving the
      # mic bare. Second caller drops out rather than queueing.
      exec 9>"''${XDG_RUNTIME_DIR:-/tmp}/easyeffects-aec-reset.lock"
      flock -n 9 || exit 0

      notify() {
        if [ "$QUIET" = 1 ]; then return 0; fi
        notify-send -h string:x-canonical-private-synchronous:ee-aec \
          -t 3000 "Echo canceller" "$1" || true
      }

      # These talk to the instance we already suspect is wedged, so none of
      # them may block the watchdog's polling loop indefinitely.
      ee() { timeout 10 easyeffects "$@" >/dev/null 2>&1 || true; }

      node_id() {
        pw-dump 2>/dev/null \
          | jq -r --arg n "$1" 'first(.[] | select(.info.props["node.name"] == $n) | .id) // ""'
      }

      # await <node-name> <present|absent> <tries>, 200ms apart
      await() {
        local i
        for ((i = 0; i < $3; i++)); do
          if [ "$2" = present ]; then
            if [ -n "$(node_id "$1")" ]; then return 0; fi
          else
            if [ -z "$(node_id "$1")" ]; then return 0; fi
          fi
          sleep 0.2
        done
        return 1
      }

      if [ -z "$(node_id easyeffects_source)" ]; then
        notify "EasyEffects is not running"
        exit 1
      fi

      before="$(node_id ee_sie_echo_canceller)"

      # Without the throwaway preset the swap is a no-op and every reset
      # escalates to a full restart.
      if [ -f "$HOME/.local/share/easyeffects/input/${resetPresetName}.json" ]; then
        ee -l ${resetPresetName}
        await ee_sie_echo_canceller absent 15 || true
        ee -l ${presetName}

        if await ee_sie_echo_canceller present 25; then
          # A preset load can build the chain and lose it seconds later, so the
          # instantaneous check is not proof.
          sleep 3
          after="$(node_id ee_sie_echo_canceller)"
          if [ -n "$after" ] && [ "$after" != "$before" ]; then
            notify "Reset"
            exit 0
          fi
        fi
      else
        notify "Reset preset missing — run home-manager switch"
      fi

      # A same-id instance means the preset swap reused it, so its WebRTC
      # state survived and only a restart will clear it.
      notify "Restarting EasyEffects"
      ee -q
      if ! await easyeffects_source absent 25; then
        pkill -u "$(id -u)" -f '^easyeffects ' || true
        if ! await easyeffects_source absent 15; then
          pkill -9 -u "$(id -u)" -f '^easyeffects ' || true
          # Relaunching next to a live instance leaves two of them fighting
          # over the same nodes, which is worse than the stale canceller.
          if ! await easyeffects_source absent 15; then
            notify "EasyEffects will not exit — not relaunching"
            exit 1
          fi
        fi
      fi
      setsid --fork easyeffects --hide-window >/dev/null 2>&1
      if await ee_sie_echo_canceller present 50; then
        notify "Reset"
        exit 0
      fi
      notify "EasyEffects did not come back"
      exit 1
    '';
  };

  # Banks a trigger and spends it when the mic goes idle; mid-call it still
  # fires, rate-limited. Logs to the journal as `ee-watchdog` — resets are
  # audible, so a silent one is indistinguishable from the dropout it fixes.
  aecWatchdog = pkgs.writeShellApplication {
    name = "easyeffects-watchdog";
    runtimeInputs = [
      aecReset
      pkgs.pipewire
      pkgs.jq
      pkgs.gawk
      pkgs.coreutils
      pkgs.util-linux
    ];
    text = ''
      INTERVAL="''${EE_WATCHDOG_INTERVAL:-15}"
      # High on purpose: each reset is an audible rebuild, so only sustained
      # starvation should trigger one.
      XRUN_THRESHOLD="''${EE_WATCHDOG_XRUNS:-50}"
      COOLDOWN="''${EE_WATCHDOG_COOLDOWN:-120}"

      # Tabs, not spaces: PipeWire node.name can contain spaces. Emits
      # "ec-id probe-name probe-state consumers source-present mic-present";
      # first four are none/0 when the canceller is absent, last two always
      # yes/no so an empty chain is distinguishable from EE being down.
      ee_state() {
        pw-dump 2>/dev/null | jq -r '
          . as $all
          | ($all | map(select(.type == "PipeWire:Interface:Node"))) as $nodes
          | ($all | map(select(.type == "PipeWire:Interface:Port"))) as $ports
          | ($all | map(select(.type == "PipeWire:Interface:Link"))) as $links
          | ($nodes | map(select(.info.props["node.name"] == "ee_sie_echo_canceller")) | first) as $ec
          | ($nodes | map(select(.info.props["node.name"] == "easyeffects_source")) | first) as $src
          | ($nodes | map(select(.info.props["node.name"] == "${snowballDevice}")) | first) as $mic
          | (if $src == null then "no" else "yes" end) as $srcp
          | (if $mic == null then "no" else "yes" end) as $micp
          | if $ec == null or $src == null then
              ["none", "none", "none", "0", $srcp, $micp] | join("\t")
            else
              ( $ports
                | map(select(.info.props["node.id"] == $ec.id
                             and ((.info.props["port.name"] // "") | startswith("probe_"))))
                | map(.id) ) as $probe_ports
              | ( $links
                  | map(select(.info["input-port-id"] as $p | ($probe_ports | index($p)) != null))
                  | map(.info["output-node-id"]) | unique | first ) as $psrc
              | ($nodes | map(select(.id == $psrc)) | first) as $pnode
              | ($links | map(select(.info["output-node-id"] == $src.id)) | length) as $consumers
              | [ ($ec.id | tostring),
                  ($pnode.info.props["node.name"] // "none"),
                  ($pnode.info.state // "none"),
                  ($consumers | tostring),
                  $srcp,
                  $micp ] | join("\t")
            end' 2>/dev/null
      }

      # Cumulative per-node xrun counters over pw-top's last block; prints
      # nothing (not 0) on a failed sample, so it cannot masquerade as a reset.
      graph_xruns() {
        timeout 10 pw-top -b -n 2 2>/dev/null | awk '
          /ID[ ]+QUANT/ { total = 0; seen = 0; next }
          $1 ~ /^[RID]$/ { total += $9 + 0; seen = 1 }
          END { if (seen) print total + 0 }'
      }

      prev_xruns=""
      prev_probe_state=""
      prev_empty=0
      pending=""
      last_reset=0

      while true; do
        sleep "$INTERVAL"

        IFS=$'\t' read -r ec probe probe_state consumers src mic <<< "$(ee_state)" || true

        # A failed sample is not evidence of anything.
        if [ -z "''${ec:-}" ]; then continue; fi

        # Fail closed: a malformed count must not read as "mic is idle".
        case "''${consumers:-}" in ""|*[!0-9]*) consumers=1 ;; esac

        reason=""

        if [ "$ec" = none ]; then
          prev_xruns=""
          prev_probe_state=""

          # EE 8.x builds the chain on demand and drops it ~10s after the last
          # consumer leaves, so an empty chain at idle is normal. Only
          # consumers>0 makes it a fault. Debounced 4 intervals for build time.
          if [ "$src" = yes ] && [ "$mic" = yes ] && [ "$consumers" -gt 0 ]; then
            prev_empty=$((prev_empty + 1))
            if [ "$prev_empty" -ge 4 ]; then reason="chain empty"; fi
          else
            prev_empty=0
            pending=""
            continue
          fi
        else
          prev_empty=0
          # Chain-empty describes a state, not an event: spending it once the
          # chain is back would tear down a healthy one.
          if [ "$pending" = "chain empty" ]; then pending=""; fi
          xruns="$(graph_xruns || true)"

          # No "probe changed" trigger: upstream d4665ddf relinks it already,
          # and the transient "none" during relink made resets self-perpetuate.
          if [ "$prev_probe_state" = suspended ] && [ "$probe_state" = running ]; then
            reason="reference sink resumed"
          elif [ -n "$prev_xruns" ] && [ -n "$xruns" ] \
            && [ "$xruns" -ge "$prev_xruns" ] \
            && [ "$((xruns - prev_xruns))" -ge "$XRUN_THRESHOLD" ]; then
            reason="$((xruns - prev_xruns)) xruns"
          fi

          prev_probe_state="$probe_state"
          prev_xruns="$xruns"
        fi

        if [ -n "$reason" ]; then
          pending="$reason"
          logger -t ee-watchdog \
            "trigger: $reason (ec=$ec probe=$probe state=$probe_state consumers=$consumers)"
        fi
        if [ -z "$pending" ]; then continue; fi

        now="$(date +%s)"
        # chain-empty takes the cooldown path even when idle: if a reset cannot
        # fix it, the immediate path would re-fire forever.
        if [ "$consumers" -eq 0 ] && [ "$pending" != "chain empty" ]; then
          :
        elif [ "$((now - last_reset))" -ge "$COOLDOWN" ]; then
          :
        else
          continue
        fi

        opts=()
        if [ "$consumers" -eq 0 ]; then opts=(--quiet); fi
        logger -t ee-watchdog "reset: $pending"
        easyeffects-aec-reset "''${opts[@]}" || true

        pending=""
        last_reset="$now"
        # Node ids change across a rebuild, so the old sum is not comparable.
        prev_xruns=""
      done
    '';
  };
in
{
  home.packages = [ pkgs.easyeffects aecReset aecWatchdog ];

  home.file.".local/share/easyeffects/input/${presetName}.json" = {
    text = builtins.toJSON micPreset;
    force = true;
  };

  home.file.".local/share/easyeffects/input/${resetPresetName}.json" = {
    text = builtins.toJSON resetPreset;
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

  # processAllOutputs defaults true, routing playback through EE's sink; that
  # produced thousands of xruns. Lives in EE's KConfig INI, which EE rewrites at
  # runtime — set only our keys instead of symlinking.
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
