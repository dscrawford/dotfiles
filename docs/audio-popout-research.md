# Why the audio keeps popping out

*Generated: 2026-08-28 | Evidence: live journal (46 boots, 2026-07-13 → now), pw-dump,
pw-top, /proc/asound, NixOS generation history, EasyEffects runtime config | Confidence:
High on the mechanism and the start date, Medium on which symptom the user is hearing*

Follow-up to [audio-dropout-research.md](./audio-dropout-research.md) (2026-08-24). That
pass was mostly web research; this one is almost entirely local measurement, because the
answer turned out to be in this repo.

## Executive summary

There are two independent faults, and only one of them is new.

The **new** one is self-inflicted: the `easyeffects-watchdog` added in `99078d5`
(2026-08-21) has been tearing down and rebuilding the entire mic chain — echo canceller,
DeepFilterNet, gate — on a fixed 2-minute cadence for hours at a stretch, ~30 times an
hour. EasyEffects' own runtime config records **277** loads of the throwaway reset preset.
Upstream's maintainer describes exactly this operation as causing "jumps in audio level as
well as noises". That started on 2026-08-21, in generation 380, which is still the running
system.

The **old** one is the VIA Labs USB hub, which drops and re-enumerates 13–37 times a day
and has done so continuously since the journal begins on 2026-07-13. Moving it to the
CPU-attached controller (`0d:00.3`, buses 5/6) — the Aug 24 recommendation — did not help.

A third thing is true right now and worth fixing before anything else: **the denoise chain
is not loaded at all.** The graph has `ee_sie_output_level` and `ee_sie_spectrum` and
nothing else — no filter, no canceller, no DFN, no gate — and `easyeffects_source` has zero
links. The mic has been running raw since some point today.

## 1. The watchdog is the thing that started on Aug 21

### 1.1 The dates line up exactly

| Date | Event |
|---|---|
| 2026-08-21 | `e3d34d3` graph tuning, `99078d5` adds `easyeffects-watchdog` |
| 2026-08-21 23:04 | Generation **380** built — the first and only generation carrying the watchdog |
| 2026-08-21 23:18 | Home Manager switch; `~/.local/share/easyeffects/autoload/input/…` symlink mtime |
| 2026-08-21 | 17 distinct `easyeffects[pid]` in the journal (≈40 min of uptime after the switch) |
| 2026-08-22 | **233** |
| 2026-08-23 | **548** |
| 2026-08-26 | **176** |

For comparison, the whole month before the watchdog: 10 on Jul 27, 2 on Jul 29, 2 on
Aug 7. Generation 380 is still `Current`, so nothing since has changed this.

### 1.2 The cadence is exactly `COOLDOWN`

Launch timestamps on 2026-08-23, unbroken from 11:09 to 21:5x:

```
11:14 11:16 11:18 11:20 11:22 11:25 11:27 11:29 11:31 11:33 11:35 …
```

Every two minutes, all day, 46–60 process launches per hour. `COOLDOWN` in
`shared/easyeffects.nix` is `120` seconds. That is not a watchdog responding to
intermittent faults; that is a watchdog whose trigger is permanently satisfied, firing as
fast as its own rate limit allows.

### 1.3 The counter confirms it independently

`~/.config/easyeffects/db/easyeffectsrc`:

```ini
usedPresets=mic-denoise:283,rnnoise:1,mic-denoise-aec-reset:277
```

277 loads of `mic-denoise-aec-reset` — a preset whose entire purpose is to be swapped in so
the canceller instance gets destroyed. Each of those is a full teardown/rebuild of
`filter#0 → echo_canceller#0 → deepfilternet#0 → gate#0`.

Journal PID count (~993 unique) divided by resets (277) is ≈3.6 processes per reset,
consistent with two `easyeffects -l …` CLI invocations per swap plus a `easyeffects -q`
whenever a swap escalated to a full restart.

### 1.4 Why it never converges (inference, not proven)

`ee_state()` returns `"none"` for the probe when the canceller's `probe_*` ports exist but
are not yet linked. The reset path waits for the *node* to reappear
(`await ee_sie_echo_canceller present 25`) but nothing waits for the probe *link*. So:

1. Reset rebuilds the canceller. New node id, probe ports present, probe link not yet made.
2. If the rebuild completes inside one 15 s `INTERVAL`, the watchdog never observes
   `ec = none`, so it never clears `prev_probe`.
3. It samples `probe = "none"` ≠ `prev_probe`, concludes `reason="reference moved to none"`,
   and banks another reset.
4. `pending` is spent at the next cooldown expiry — 120 s later. Repeat.

That predicts precisely the observed fixed 2-minute cadence. It is consistent with all the
evidence but not directly proven, because the watchdog logs nothing — it only calls
`notify-send`, and those notifications are not journaled. **Adding a `logger` line to each
trigger branch would settle it in one session.**

The Aug 24 research already recommended softening the `reference moved` trigger (§2.2) and
raising `XRUN_THRESHOLD` (key takeaway 5). Neither was applied — generation 380 predates
that document by three days, and there has been no rebuild since.

### 1.5 What it sounds like

Upstream, on exactly this technique
([wwmm/easyeffects#3851](https://github.com/wwmm/easyeffects/issues/3851)):

> "Destroying the whole plugin instance and recreating it. It is doable. But **jumps in
> audio level as well as noises can happen when doing things this way.**"

Note the blast radius: `processAllOutputs=false` is set, so playback bypasses EasyEffects
entirely. **This fault can only affect the microphone path** — your voice in calls, or
anything monitoring `easyeffects_source`. If what is popping out is the *speakers*, this is
not the cause and §2 is the better lead.

## 2. The USB hub is not new, and moving it did not fix it

Hub disconnect lines per day (each drop logs twice — USB 2.0 hub at `5-2`, USB 3.0 hub at
`6-2` — so halve these for real drop counts):

```
Jul 14: 26   Jul 22: 52   Jul 28: 48   Aug  6: 52   Aug  7: 74   Aug 12: 70
Aug 17: 50   Aug 18: 58   Aug 19: 74   Aug 24: 52   Aug 26: 50   Aug 27: 36
```

Roughly 13–37 real drops per day, every day, with no step change anywhere — including
across the move to the CPU-attached controller. The journal only reaches back to
2026-07-13, so "when did it start" is unanswerable from logs; what is answerable is that it
predates every software change under investigation.

A representative drop, 2026-08-27 10:30:41 → 10:34:17, 3m36s of outage taking the mic, the
Logitech receiver, the downstream hub and the keyboard with it:

```
10:30:41 usb 5-2:     USB disconnect, device number 22
10:30:41 usb 5-2.1:   USB disconnect (Blue Snowball)
10:30:41 usb 5-2.2:   USB disconnect (Logitech USB Receiver)
10:30:42 usb 5-2.3:   USB disconnect (downstream 1a40:0801 hub)
10:30:42 usb 6-2:     USB disconnect
10:34:17 usb 6-2:     new SuperSpeed USB device number 7 … VIA Labs, Inc. USB3.0 Hub
```

**The hub itself is the fault.** The Aug 24 doc's §1.3 hypothesis — chipset controller or
bridge chain — is now falsified by experiment: same hub, different controller, same
failure rate. What remains from that document is the VIA VL81x prior art and the BIOS
update (4805, three AGESA revisions stale).

As of today 09:10 the Snowball is no longer on the hub — it disconnected at 09:10:06 and
reappeared at 09:10:37 on `1-3`, a direct chipset port (`/proc/asound/cards` now reads
`usb-0000:08:00.1-3`). That removes the mic from the hub's blast radius. The keyboard and
mouse are still on it.

## 3. The Aug 17 log line is cosmetic

`spa.alsa: … poll fd error/hangup (card removed?), removing poll sources` first appears at
2026-08-17T16:10:35 and looks alarming, but it is not a regression:

- Generation 372, built 2026-08-17 15:24, is the first with **pipewire 1.6.8**
  (369–371 are 1.6.7), from the channel bump `26.11.20260714` → `26.11.20260816`.
- Before that date the same hub drops produced only `snd_pcm_drop: No such device` /
  `close failed: No such device` — see 2026-08-12 09:03:01, 14:33:28, 15:56:23.
- The underlying event rate is unchanged across the boundary (§2).

It is a new message for an old event: PipeWire noticing `POLLHUP` on a yanked ALSA card
([Arch forums thread on the same message](https://bbs.archlinux.org/viewtopic.php?pid=2306044#p2306044)).
Do not chase it.

## 4. Ruled out on the output path

Everything on the speaker side measures clean, which is why §1 and §2 are both mic-side
conclusions:

| Check | Result |
|---|---|
| `alsa_output.pci-0000_0d_00.4.analog-stereo` PCM | `state: RUNNING`, continuous, never closed |
| `session.suspend-timeout-seconds` on the sink | `0` — applied, sink never suspends |
| `api.alsa.headroom` | `1024` — applied |
| xruns (`pw-top -b -n 3`) | `ERR = 0` on every node, three samples |
| `snd_hda_intel power_save` | `10`, but irrelevant: the PCM never closes, so the codec never idles into power-down |
| HDMI / default-sink switching | no switch events since Aug 20; `snd_hda_intel` lines are boot-time only |
| Bluetooth audio | no A2DP device connected since Aug 20 — only endpoint registration at session start |

One correction to the Aug 24 doc while here: §2.5 said `node.latency = 512/48000` +
`node.lock-quantum` did not take. It does now — the Snowball node reports
`"node.latency": "512/48000"`, `"node.lock-quantum": true`, and `pw-top` shows the mic at
`QUANT 1024` following the sink's 2048. The comment at `hosts/local/audio.nix:58-65` is
accurate about intent; it is the graph quantum, not the node property, that lands at 1024.

## 5. The chain is dead right now

```
$ pw-dump | jq … node.name | grep ^ee_
ee_sie_output_level
ee_sie_spectrum
ee_soe_output_level
ee_soe_spectrum
ee_test_signals
```

No `ee_sie_filter`, no `ee_sie_echo_canceller`, no `ee_sie_deepfilternet`, no `ee_sie_gate`.
`easyeffects_source` has zero links. Meanwhile `easyeffectsrc` still claims
`lastLoadedInputPreset=mic-denoise` and `plugins=filter#0,echo_canceller#0,deepfilternet#0,gate#0`.

So EasyEffects believes the preset is loaded and the graph disagrees. The most likely
sequence: the Snowball was unplugged at 09:10:06 and replugged 31 s later, and the autoload
rule did not re-fire on the returning device.

This is the failure mode the reset script's own comment warns about — "leave the mic with no
canceller, no DFN and no gate, **silently**" — and nothing detects it. The watchdog cannot:
`ee_state()` returns `none\tnone\tnone\t0` when the canceller is absent, and the loop treats
that as "nothing to do" and `continue`s. The one state that genuinely needs intervention is
the one state it ignores.

## Key takeaways

1. **Right now:** `easyeffects -l mic-denoise` — the denoise chain is not loaded.
2. **The thing that started on Aug 21 is the watchdog**, not the hardware. 277 recorded
   chain rebuilds, one every 120 s for hours at a time. Either disable it or fix the
   trigger before anything else.
3. **Minimum fix to the watchdog**, all in `shared/easyeffects.nix`:
   - drop the `reference moved` branch (upstream `d4665ddf` already relinks on output
     change — established in the Aug 24 doc §2.2);
   - raise `XRUN_THRESHOLD` well above 3;
   - add `logger -t ee-watchdog "$reason"` on every fire so this is diagnosable next time;
   - invert the dead-chain case: `ec = none` while the mic exists should *trigger* a
     preset load, not `continue`.
4. **The hub is the hardware fault and the controller move disproved the chipset theory.**
   Retire the VIA hub, or at minimum keep audio off it — which is now accidentally true
   since this morning's replug.
5. **Ignore the `poll fd error/hangup` line.** New in pipewire 1.6.8 (gen 372, Aug 17),
   same underlying event as before.
6. **Nothing on the output path is misbehaving**, so if the symptom is the speakers rather
   than the mic, none of the above is the cause and the investigation needs to restart from
   a timestamped observation.
7. Generation 380 predates the Aug 24 research; none of its recommendations are live. A
   rebuild is required for any change here to take effect.

## Method

No new web research beyond one confirmation of the pipewire log-line provenance — the
external groundwork is in the Aug 24 document, and this question turned out to be
answerable from local state. Everything above is measured: `journalctl -b all` across 46
boots, `nixos-rebuild list-generations` cross-referenced against each generation's
`pipewire.service` store path, `pw-dump`, `pw-top -b`, `/proc/asound/*/pcm*/sub0/status`,
`/sys/module/snd_hda_intel/parameters/*`, and EasyEffects' own `easyeffectsrc` counters.

Sub-questions: when did each symptom first appear in the logs; did the Aug 17 channel bump
change behaviour or only logging; did moving the hub to the CPU controller change the drop
rate; is the output path suspending or xrunning; what is the watchdog actually doing.

**Open:** which symptom "popping out" refers to — mic or speakers — and direct proof of the
watchdog's trigger, which needs the logging in takeaway 3.

## Sources

1. [wwmm/easyeffects#3851](https://github.com/wwmm/easyeffects/issues/3851) — maintainer on
   plugin-instance rebuilds causing level jumps and noise.
2. [Arch Linux Forums — USB device / `poll fd error/hangup`](https://bbs.archlinux.org/viewtopic.php?pid=2306044#p2306044)
   — the message accompanies USB audio removal; not itself a fault.
3. [audio-dropout-research.md](./audio-dropout-research.md) (2026-08-24) — VIA VL81x prior
   art, AMD 500-series USB history, BIOS 4805 currency, EasyEffects 8.2.8 source analysis.
