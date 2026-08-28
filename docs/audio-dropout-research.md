# Audio dropouts and doubled mic: are the proposed fixes robust?

*Generated: 2026-08-24 | Sources: 16 | Confidence: High on USB cause, Medium on the doubled-voice mechanism*

Verification pass over the five fixes proposed earlier. Two survive unchanged, one
was wrong about the mechanism, one is redundant with an upstream fix, and the
doubled-voice diagnosis needs reassigning from the echo canceller to DeepFilterNet.

## Executive summary

The USB dropouts are real, ongoing, and escalating — the hub dropped twice more
*during this research* (12:04:54, and again 16 seconds after reconnecting at
12:07:13). But `usbcore.autosuspend=-1` is not the fix: the kernel's own
documentation says autosuspend suspends a device, it does not disconnect and
re-enumerate it, and hubs defaulting to `power/control=auto` is deliberate kernel
behaviour, not a misconfiguration on this box. The higher-value actions are a BIOS
update (three AGESA revisions behind, on the exact chipset family AMD root-caused
for USB dropouts) and moving the Snowball to the CPU-attached USB controller, which
is currently sitting completely empty.

On the EasyEffects side the premise of `99078d5` holds up — `clear_data()` still
early-returns for the WebRTC canceller in the installed 8.2.8, so the preset-swap
rebuild is still the only in-process reset. But the "reference moved" trigger now
duplicates an upstream fix that shipped in 8.2.8, and the doubled-voice symptom
matches a known DeepFilterNet latency-accumulation bug far better than it matches
AEC delay drift.

## 1. The USB dropouts

### 1.1 It is not autosuspend

The kernel's USB power management document is explicit that autosuspend is a
*suspend*, not a disconnect:

> "When a particular device is turned off while the system as a whole remains
> running, we call it a 'dynamic suspend' (also known as a 'runtime suspend' or
> 'selective suspend')."

Losing VBUS — which is what would produce the observed `USB disconnect` plus full
re-enumeration — is a separate mechanism, port power control:

> "Upon receiving a ClearPortFeature(PORT_POWER) request a USB port is logically
> off, and may trigger the actual loss of VBUS to the port."

([kernel.org USB power management](https://www.kernel.org/doc/Documentation/usb/power-management.txt))

The same document also explains the `power/control` values seen locally:

> "by default the kernel disables autosuspend (the power/control attribute is
> initialized to 'on') for all devices other than hubs"

So `1-2/power/control = auto` on the hub and `on` on the Snowball is stock kernel
behaviour, not drift. There is a historical caveat — a v3.8 regression made hubs
ignore `usbcore.autosuspend`, later addressed by
[usb: hub: Prevent hub autosuspend if usbcore.autosuspend is -1](https://groups.google.com/g/linux.kernel/c/qjLE6FWimGs)
— but that only affects whether the parameter is honoured, not whether autosuspend
can cause a re-enumeration in the first place.

Community reports do confirm `usbcore.autosuspend=-1` works for what it does
([Arch forums](https://bbs.archlinux.org/viewtopic.php?id=303477),
[AtomMiner KB](https://kb.atomminer.com/kb/usb-autosuspend-issues/)), while also
noting the limit that applies here: poor-quality hub silicon disconnects regardless
of autosuspend settings.

**Verdict: downgrade.** Harmless and cheap, but low expected yield. Not the fix.

### 1.2 The chipset is the one AMD root-caused

Local hardware, confirmed:

| Item | Value |
|---|---|
| Board | ASUSTeK TUF GAMING X570-PLUS (WI-FI) |
| BIOS | **4805, dated 2023-08-14** |
| Flaky controller | `0000:08:00.1` — `1022:149C`, xhci_hcd |
| Its bridge chain | `00:01.2` → `02:00.0` (`1022:57ad`) → `03:08.0` (`1022:57a4`) — X570 chipset |
| Hub | VIA Labs `2109:0815` / `2109:2815` at `1-2` |

X570 is a 500-series chipset, and AMD confirmed, root-caused, and shipped a fix for
intermittent USB dropouts on exactly this family. The published symptom list is a
close match: USB port dropout, USB 2.0 audio crackling, and a PCIe Gen 4 interaction
([AMD/Guru3D](https://www.guru3d.com/news-story/amd-is-investigating-usb-problems-with-500-series-chipsets.html),
[KitGuru root cause](https://www.kitguru.net/components/motherboard/joao-silva/amd-has-discovered-the-root-cause-of-usb-connectivity-issues-fix-coming-in-new-bios-update/),
[VideoCardz on AGESA 1.2.0.2](https://videocardz.com/newz/amd-announces-agesa-1-2-0-2-that-solves-intermittent-usb-connectivity-issues)).
ASUS shipped AGESA 1.2.0.2 for 500-series boards in April 2021
([Neowin](https://www.neowin.net/news/agesa-1202-update-for-fixing-usb-issues-rolling-out-to-asus-500-series-boards/)).

BIOS 4805 is well past 1.2.0.2, so the *original* bug should already be patched —
but it is still roughly two and a half years and three AGESA revisions stale.
Available since ([ASUS BIOS downloads](https://www.asus.com/us/motherboards-components/motherboards/tuf-gaming/tuf-gaming-x570-plus-wi-fi/helpdesk_bios?model2Name=TUF-GAMING-X570-PLUS-WI-FI)):

- 5021 — 2024-11-04 — AGESA ComboV2 PI 1.2.0.Cc
- 5031 — 2025-04-01 — AGESA ComboV2 PI 1.2.0.E *(latest non-beta)*
- 5041 — 2025-08-14 — AGESA ComboV2 PI 1.2.0.F (beta)
- 5044 — 2026-02-02 — beta, "improve system compatibility"

The AMD workaround set repeatedly reported by users is *Power Supply Idle Control →
Typical Current Idle* and disabling *Global C-State Control*
([Overclock.net](https://www.overclock.net/threads/usb-issues-with-amd-motherboards.1774959/),
[Linus Tech Tips](https://linustechtips.com/topic/1315038-b550x570-ryzen-usb-issues-and-disconnects-might-release-a-fix-in-april/)).
Reported effectiveness is inconsistent — it works for some systems and not others —
so treat it as a diagnostic probe, not a fix.

**Verdict: promote.** BIOS update is the highest-value low-risk action.

### 1.3 There is an empty CPU-attached controller

Three xHCI controllers are present, all `1022:149c`:

| Controller | Buses | Currently attached |
|---|---|---|
| `08:00.1` (chipset) | 1, 2 | **the flaky VIA hub**, Steam Controller puck, webcam |
| `08:00.3` (chipset) | 3, 4 | wireless device, AURA LED controller |
| `0d:00.3` (CPU) | 5, 6 | **nothing** |

`0d:00.3` sits next to `0d:00.4`, the onboard analog audio, on the CPU root complex
rather than behind the chipset bridges. Moving the Snowball there removes both
suspects — the VIA hub and the chipset controller — in one step, and it is free.

This also matters because the hub's outage durations are wrong for a controller
glitch. Drops this boot ran 8 to 19 minutes before re-enumeration
(11:21:53 → 11:41:01, 11:43:02 → 11:51:15), which looks like the hub losing power
and staying down, not a link error the host recovers from. There were no `xhci`
error lines at all around any drop. VIA Labs VL81x hubs have a documented history of
random resets and disconnects on Linux, including with external power applied
([Arch forums](https://bbs.archlinux.org/viewtopic.php?id=291592),
[raspberrypi/linux#4114](https://github.com/raspberrypi/linux/issues/4114),
[raspberrypi/linux#5959](https://github.com/raspberrypi/linux/issues/5959)).

**Verdict: this replaces "move it to a rear port" as the first thing to try.**

## 2. The EasyEffects watchdog

### 2.1 The premise still holds in the installed version

Installed: **easyeffects 8.2.8**, which is the newest tag — there is no 8.2.9 or
8.3.0. The reasoning in `99078d5`'s commit message was checked against v8.2.8's
`src/echo_canceller.cpp` and is still accurate:

```cpp
void EchoCanceller::clear_data() {
  if (lv2_wrapper == nullptr) {
    return;                       // <- webrtc canceller: always taken
  }
  ...
  setup();                        // <- so init_webrtc() is never reached
}
```

`init_webrtc()` is only called from `setup()`, and `setup()` is only reached past
that early return or on construction. So the UI's reset genuinely cannot clear the
WebRTC state, and rebuilding the plugin instance really is the only route.

**Verdict: unchanged. The reset mechanism is sound and still necessary.**

### 2.2 The "reference moved" trigger is now redundant

Upstream commit
[d4665ddf](https://github.com/wwmm/easyeffects/commit/d4665ddf) (2026-05-20):

> "Relinking the microphone pipeline when output device changes so that the echo
> canceller gets the correct device for its probes. We now also link mono channels
> to both the left and right channels of the neighbor node"

followed by `26e2723f` (2026-05-21) "Improved probe port handling". These closed
[#5095 "Echo Canceller isn't attached to a new default output device while in
use"](https://github.com/wwmm/easyeffects/issues/5095).

Verified as ancestors of the installed build: `compare/d4665ddf...v8.2.8` reports
`behind_by=0`, i.e. **both fixes are in 8.2.8**.

Two consequences:

1. The watchdog's `reason="reference moved to $probe"` branch now largely duplicates
   upstream relinking, and it demonstrably misfires on unrelated graph churn — it
   fired at 11:51:18, three seconds after the USB hub re-enumerated at 11:51:15.
2. The mono-channel probe half of that commit is directly relevant, because the
   Snowball is mono (`mono-fallback`, `S16LE 1 48000`). Before this fix, mono mics
   left one AEC probe unlinked. That would have been an excellent explanation for
   the doubled voice — but it is already fixed in what is installed, so it is ruled
   out rather than confirmed.

**Verdict: soften or drop the probe-change trigger.** Keep the sink-resumed one.

### 2.3 The doubled voice is more likely DeepFilterNet than the AEC

[wwmm/easyeffects#3851](https://github.com/wwmm/easyeffects/issues/3851) reports
that DeepFilterNet accumulates processing delay under CPU load and never recovers:

> "when I enable the DeepFilterNet plugin, I observe that audio latency begins to
> accumulate over time — especially after launching other applications or under
> moderate CPU load. [...] Critically, even after CPU usage returns to normal, this
> accumulated delay does not return to the original baseline latency."

with measured numbers of ~15 ms baseline, ~55 ms with DFN on, **100 ms+ after load**,
and toggling the plugin off and on again returning straight to 100 ms+ rather than
55 ms. The maintainer's response is the same conclusion the repo's watchdog reached
independently:

> "As I am not this plugin's author the only way is an ugly way. Destroying the
> whole plugin instance and recreating it. It is doable. But **jumps in audio level
> as well as noises can happen when doing things this way**."

That last clause is a direct warning about the reset path in `easyeffects-aec-reset`.

Two things follow. First, the "under heavy CPU load" qualifier fits DFN latency
accumulation much better than it fits WebRTC delay drift — the load dependence is
the reported trigger, not an inference. Second, the existing preset swap already
rebuilds DFN along with the canceller, so the medicine is right even though the
trigger is named for the wrong plugin.

**Gap, stated plainly:** this is not confirmed on this machine. There were zero
`Underrun detected (RTF: ...)` lines in the journal this boot. The reporter in #3851
was on the LADSPA DeepFilterNet build; EasyEffects 8.x uses its own native plugin,
which may simply not emit those warnings. So the mechanism is plausible and well
matched, not proven here.

### 2.4 Realtime scheduling is fine — one worry removed

In #3851 the maintainer flags
[pipewire#4748](https://gitlab.freedesktop.org/pipewire/pipewire/-/issues/4748),
where an `xdg-desktop-portal` bug prevents PipeWire from acquiring realtime
priority, and suggests checking that before adding reset machinery. Checked locally:

```
2207 data-loop.0  RR 20   (easyeffects)
2356 data-loop.0  RR 20   (pipewire)
2357 data-loop.0  RR 20   (wireplumber)
2401 data-loop.0  RR 20   (pipewire-pulse)
```

All four have `SCHED_RR` at priority 20 and rtkit is running. The portal bug does
not apply here, so xruns under load are genuine CPU starvation, not a missing RT
grant. Raising the xrun threshold is therefore the right response, not a workaround
for a misconfiguration.

### 2.5 Graph tuning: applied, but not as documented

Verified live on both sinks: `api.alsa.headroom=1024` and
`session.suspend-timeout-seconds=0` are applied. The mic props could not be checked
because the mic was disconnected at the time.

The `node.latency = 512/48000` + `node.lock-quantum` pair does not produce a 512
graph. Observed quantum was 1024 on the mic with the sink driving at 2048 — the mic
is a follower, not the driver, so it does not set the graph quantum. This is
benign and arguably better than intended, since the standard advice for
EasyEffects crackling under CPU load is to *raise* `min-quantum` to 1024
([Linux Mint guide](https://forums.linuxmint.com/viewtopic.php?t=450701)). Only the
comment in `hosts/local/audio.nix` is wrong.

Also verified: the watchdog's `ee_state` jq degrades correctly to
`none\tnone\tnone\t0` when the canceller is absent from the graph, which it is
whenever the USB mic drops. That path is robust.

## Key takeaways

1. **Do first, costs nothing:** move the Snowball to a port on `0d:00.3` (bus 5/6,
   CPU-attached, currently empty). Removes the VIA hub and the chipset controller
   from the picture in one move.
2. **Do second:** update BIOS 4805 → 5031 (AGESA 1.2.0.E). Three revisions of AGESA
   USB fixes on the chipset family AMD root-caused for this exact symptom.
3. **Drop `usbcore.autosuspend=-1` from the plan** as a *fix*. Autosuspend does not
   cause re-enumeration. Keep it only as free insurance if you want it.
4. **Keep the reset mechanism**, verified still necessary against v8.2.8 source.
5. **Change the triggers:** gate the xrun trigger on `consumers -eq 0` so load
   spikes never cut a live call, raise `XRUN_THRESHOLD` well above 3, and
   soften the probe-change trigger now that upstream relinks on its own.
6. **Rename the concept:** the reset is as much a DeepFilterNet delay flush as an
   AEC reset, and DFN is the better-matching explanation for the doubled voice.
7. **Fix the comment** in `hosts/local/audio.nix:63-64` — the graph runs at 1024,
   not 512, and that is fine.

## Sources

1. [kernel.org — USB Power Management](https://www.kernel.org/doc/Documentation/usb/power-management.txt) — autosuspend is a suspend, not a disconnect; hubs default to `auto`.
2. [usb: hub: Prevent hub autosuspend if usbcore.autosuspend is -1](https://groups.google.com/g/linux.kernel/c/qjLE6FWimGs) — historical v3.8 regression where hubs ignored the parameter.
3. [Arch Linux Forums — USB disconnects](https://bbs.archlinux.org/viewtopic.php?id=303477) — autosuspend=-1 as a working mitigation.
4. [AtomMiner KB — USB autosuspend disconnects active devices](https://kb.atomminer.com/kb/usb-autosuspend-issues/) — symptom description.
5. [Guru3D — AMD investigating 500-series USB problems](https://www.guru3d.com/news-story/amd-is-investigating-usb-problems-with-500-series-chipsets.html) — issue confirmation.
6. [KitGuru — AMD root cause found](https://www.kitguru.net/components/motherboard/joao-silva/amd-has-discovered-the-root-cause-of-usb-connectivity-issues-fix-coming-in-new-bios-update/) — dropout, USB 2.0 audio crackling, PCIe Gen4 interaction.
7. [VideoCardz — AGESA 1.2.0.2](https://videocardz.com/newz/amd-announces-agesa-1-2-0-2-that-solves-intermittent-usb-connectivity-issues) — official fix announcement.
8. [Neowin — ASUS 500-series AGESA 1.2.0.2 rollout](https://www.neowin.net/news/agesa-1202-update-for-fixing-usb-issues-rolling-out-to-asus-500-series-boards/) — vendor rollout timing.
9. [Overclock.net — USB issues with AMD motherboards](https://www.overclock.net/threads/usb-issues-with-amd-motherboards.1774959/) — Power Supply Idle Control / C-State workarounds and their inconsistency.
10. [Linus Tech Tips — B550/X570 USB disconnects](https://linustechtips.com/topic/1315038-b550x570-ryzen-usb-issues-and-disconnects-might-release-a-fix-in-april/) — same workaround set.
11. [ASUS TUF GAMING X570-PLUS (WI-FI) BIOS downloads](https://www.asus.com/us/motherboards-components/motherboards/tuf-gaming/tuf-gaming-x570-plus-wi-fi/helpdesk_bios?model2Name=TUF-GAMING-X570-PLUS-WI-FI) — 5021 / 5031 / 5041 / 5044 and their AGESA versions.
12. [Arch Linux Forums — devices on a USB hub resetting constantly](https://bbs.archlinux.org/viewtopic.php?id=291592) — VL817/VL813 resets on Linux.
13. [raspberrypi/linux#4114 — VL812 USB HUB](https://github.com/raspberrypi/linux/issues/4114) — VIA hub instability.
14. [wwmm/easyeffects#5095](https://github.com/wwmm/easyeffects/issues/5095) — AEC not reattached on output device change; fixed by d4665ddf, in 8.2.8.
15. [wwmm/easyeffects#3851](https://github.com/wwmm/easyeffects/issues/3851) — DeepFilterNet latency accumulation under load; maintainer confirms instance rebuild is the only fix and warns of level jumps and noise.
16. [Linux Mint Forums — crackling on high CPU usage with pipewire + EasyEffects](https://forums.linuxmint.com/viewtopic.php?t=450701) — raise min-quantum to 1024.

## Methodology

Eight web/news queries plus GitHub API queries against `wwmm/easyeffects` (issue
search, commit log filtered to 2026-04→2026-06, `contents` at tag `v8.2.8`, and a
`compare` to establish commit ancestry). Deep-read five sources in full. Every
hardware claim was checked against live `sysfs`, `pw-dump`, `pw-top`, `ps -L`, and
`journalctl` output on this machine rather than assumed.

Sub-questions investigated: does USB autosuspend cause re-enumeration; is the
AMD 500-series USB bug applicable and patched; is the VIA hub independently
suspect; is the EasyEffects reset premise still true in the installed version;
what actually explains a doubled voice under CPU load.

Unresolved: DeepFilterNet latency accumulation is not directly confirmed on this
machine (no underrun lines in the journal; EE 8.x's native DFN may not log them).
Measuring input pipeline latency before and after a sustained load spike would
settle it — that test needs the mic to stay connected, which is currently the
blocker.
