# Why the audio keeps popping out

*2026-08-28. Evidence: journal (46 boots, 2026-07-13 → now), pw-dump, pw-top,
/proc/asound, NixOS generations, EasyEffects runtime config. High confidence on the
mechanism and start date; medium on which symptom the user hears.*

Follow-up to [audio-dropout-research.md](./audio-dropout-research.md), from local
measurement.

## Summary

Two independent faults, one new:

- **New, self-inflicted:** `easyeffects-watchdog` (`99078d5`, 2026-08-21, generation
  380, still current) rebuilds the whole mic chain (canceller, DeepFilterNet, gate)
  every 2 minutes for hours, ~30 times an hour: **277** recorded loads of the reset
  preset. Upstream says this operation causes "jumps in audio level as well as noises".
- **Old:** the VIA Labs hub drops and re-enumerates 13–37 times a day since the journal
  begins (2026-07-13). Moving it to the CPU-attached `0d:00.3` didn't help.
- **Right now the denoise chain isn't loaded**: only `ee_sie_output_level` and
  `ee_sie_spectrum` exist and `easyeffects_source` has no links. The mic is raw.

## 1. The watchdog started on Aug 21

| Date | Event |
|---|---|
| 2026-08-21 | `e3d34d3` graph tuning; `99078d5` adds the watchdog |
| 2026-08-21 23:04 | generation **380** built, the only one with the watchdog |
| 2026-08-21 | 17 distinct `easyeffects[pid]` in ~40 min after the switch |
| 2026-08-22 / 23 / 26 | **233** / **548** / **176** |

The month before: 10 on Jul 27, 2 on Jul 29, 2 on Aug 7.

Launches on 2026-08-23, unbroken 11:09–21:5x, track `COOLDOWN` (120 s) exactly:

```
11:14 11:16 11:18 11:20 11:22 11:25 11:27 11:29 11:31 11:33 11:35 …
```

`~/.config/easyeffects/db/easyeffectsrc`:

```ini
usedPresets=mic-denoise:283,rnnoise:1,mic-denoise-aec-reset:277
```

~993 PIDs / 277 resets ≈ 3.6 processes per reset: two `easyeffects -l` per swap plus
`easyeffects -q` when a swap escalated to a restart.

**Why it never converges (inferred).** `ee_state()` reports probe `none` when the
canceller's `probe_*` ports exist but aren't linked yet. The reset waits for the node
(`await ee_sie_echo_canceller present 25`), not the probe link. If the rebuild finishes
inside one 15 s `INTERVAL`, the watchdog never sees `ec = none`, so `prev_probe` isn't
cleared; it then samples `probe = none` ≠ `prev_probe`, banks `reference moved to none`,
and fires at the next cooldown expiry. That predicts the fixed 2-minute cadence. The
watchdog only calls `notify-send` (unjournaled), so a `logger` line would prove it.

Blast radius: `processAllOutputs=false`, so playback bypasses EasyEffects. This fault
**only affects the mic**. If the speakers are popping, see §2.

## 2. The USB hub: not new, not fixed by moving it

Hub disconnect lines per day (each drop logs twice, `5-2` and `6-2`; halve for drops):

```
Jul 14: 26   Jul 22: 52   Jul 28: 48   Aug  6: 52   Aug  7: 74   Aug 12: 70
Aug 17: 50   Aug 18: 58   Aug 19: 74   Aug 24: 52   Aug 26: 50   Aug 27: 36
```

No step change anywhere, including across the controller move. A 3m36s drop taking the
mic, Logitech receiver, downstream hub and keyboard:

```
10:30:41 usb 5-2:     USB disconnect, device number 22
10:30:41 usb 5-2.1:   USB disconnect (Blue Snowball)
10:30:41 usb 5-2.2:   USB disconnect (Logitech USB Receiver)
10:30:42 usb 5-2.3:   USB disconnect (downstream 1a40:0801 hub)
10:30:42 usb 6-2:     USB disconnect
10:34:17 usb 6-2:     new SuperSpeed USB device number 7 … VIA Labs, Inc. USB3.0 Hub
```

**The hub itself is the fault**; same hub, different controller, same rate falsifies
the chipset theory. Since 09:10 today the Snowball is on direct chipset port `1-3`
(`usb-0000:08:00.1-3`), outside the hub; keyboard and mouse are still on it.

## 3. The Aug 17 log line is cosmetic

`spa.alsa: … poll fd error/hangup (card removed?)` first appears 2026-08-17T16:10:35,
with generation 372, the first on **pipewire 1.6.8** (channel `26.11.20260714` →
`26.11.20260816`). Earlier, the same drops logged `snd_pcm_drop: No such device`, and the
event rate didn't change. New message, old event
([Arch](https://bbs.archlinux.org/viewtopic.php?pid=2306044#p2306044)).

## 4. Output path is clean

| Check | Result |
|---|---|
| `alsa_output.pci-0000_0d_00.4.analog-stereo` PCM | `RUNNING`, never closed |
| `session.suspend-timeout-seconds` | `0` |
| `api.alsa.headroom` | `1024` |
| xruns (`pw-top -b -n 3`) | `ERR = 0` everywhere |
| `snd_hda_intel power_save` | `10`, irrelevant: the PCM never closes |
| HDMI / default-sink switching | none since Aug 20 |
| Bluetooth audio | no A2DP device since Aug 20 |

Correction to the earlier doc: the Snowball does report `node.latency 512/48000` and
`node.lock-quantum true`; the graph quantum lands at 1024 following the sink's 2048.

## 5. The chain is dead

```
$ pw-dump | jq … node.name | grep ^ee_
ee_sie_output_level
ee_sie_spectrum
ee_soe_output_level
ee_soe_spectrum
ee_test_signals
```

`easyeffectsrc` still claims `lastLoadedInputPreset=mic-denoise` with
`filter#0,echo_canceller#0,deepfilternet#0,gate#0`. Likely the 09:10 replug didn't
re-fire autoload. The watchdog can't see it: `ee_state()` returns `none\tnone\tnone\t0`
and the loop `continue`s, ignoring the one state that needs action.

## Takeaways

1. Now: `easyeffects -l mic-denoise`.
2. The Aug 21 change is the watchdog, not hardware. Disable it or fix its trigger first.
3. In `shared/easyeffects.nix`: drop `reference moved` (upstream `d4665ddf` relinks);
   raise `XRUN_THRESHOLD` well above 3; `logger -t ee-watchdog "$reason"` on every
   fire; make `ec = none` with the mic present *trigger* a preset load.
4. Retire the VIA hub, or keep audio off it.
5. Ignore `poll fd error/hangup`.
6. If the symptom is the speakers, none of this is the cause; restart from a timestamped
   observation.
7. Generation 380 predates the Aug 24 research; any change needs a rebuild.
