# Audio dropouts and doubled mic: are the proposed fixes robust?

*2026-08-24. 16 sources. High confidence on the USB cause, medium on the doubled-voice
mechanism.*

Verification of five earlier fixes: two survive, one had the wrong mechanism, one
duplicates an upstream fix, and the doubled voice belongs to DeepFilterNet, not the
echo canceller.

## Summary

The USB hub keeps dropping (twice more during this research: 12:04:54, and 16 s after
reconnecting at 12:07:13). `usbcore.autosuspend=-1` is not the fix: autosuspend
suspends, it doesn't disconnect and re-enumerate, and hubs defaulting to
`power/control=auto` is stock. Better: update the BIOS (three AGESA revisions behind,
on the chipset family AMD root-caused for USB dropouts) and move the Snowball to the
empty CPU-attached controller.

`99078d5`'s premise holds: `clear_data()` still early-returns for the WebRTC canceller
in 8.2.8, so the preset-swap rebuild is the only in-process reset. The "reference
moved" trigger duplicates an 8.2.8 upstream fix, and the doubled voice matches a known
DeepFilterNet latency-accumulation bug better than AEC drift.

## 1. USB dropouts

### Not autosuspend

[kernel.org USB power management](https://www.kernel.org/doc/Documentation/usb/power-management.txt):
autosuspend is a "dynamic suspend"; losing VBUS (which gives `USB disconnect` and
re-enumeration) is port power control. "By default the kernel disables autosuspend …
for all devices other than hubs", so `1-2/power/control = auto` on the hub and `on` on
the Snowball is normal. Reports confirm `autosuspend=-1` works for what it does, and
that poor hub silicon disconnects regardless
([Arch](https://bbs.archlinux.org/viewtopic.php?id=303477)).

**Verdict: downgrade.** Harmless, low yield.

### The chipset AMD root-caused

| Item | Value |
|---|---|
| Board | ASUS TUF GAMING X570-PLUS (WI-FI) |
| BIOS | **4805, 2023-08-14** |
| Flaky controller | `0000:08:00.1`, `1022:149C`, xhci_hcd |
| Bridge chain | `00:01.2` → `02:00.0` (`1022:57ad`) → `03:08.0` (`1022:57a4`), X570 chipset |
| Hub | VIA Labs `2109:0815` / `2109:2815` at `1-2` |

AMD root-caused and fixed 500-series USB dropouts (port dropout, USB 2.0 audio
crackling, PCIe Gen 4 interaction) in AGESA 1.2.0.2, April 2021
([KitGuru](https://www.kitguru.net/components/motherboard/joao-silva/amd-has-discovered-the-root-cause-of-usb-connectivity-issues-fix-coming-in-new-bios-update/),
[Neowin](https://www.neowin.net/news/agesa-1202-update-for-fixing-usb-issues-rolling-out-to-asus-500-series-boards/)).
4805 has that, but newer BIOSes exist
([ASUS](https://www.asus.com/us/motherboards-components/motherboards/tuf-gaming/tuf-gaming-x570-plus-wi-fi/helpdesk_bios?model2Name=TUF-GAMING-X570-PLUS-WI-FI)):
5021 (2024-11, AGESA 1.2.0.Cc), **5031 (2025-04, 1.2.0.E, latest non-beta)**, 5041
(beta, 1.2.0.F), 5044 (beta, 2026-02).

User-reported workarounds (*Power Supply Idle Control → Typical Current Idle*, *Global
C-State Control* off) work inconsistently; a probe, not a fix
([Overclock.net](https://www.overclock.net/threads/usb-issues-with-amd-motherboards.1774959/)).

**Verdict: promote** the BIOS update.

### An empty CPU-attached controller

| Controller | Buses | Attached |
|---|---|---|
| `08:00.1` (chipset) | 1, 2 | **the VIA hub**, Steam Controller puck, webcam |
| `08:00.3` (chipset) | 3, 4 | wireless device, AURA LED |
| `0d:00.3` (CPU) | 5, 6 | **nothing** |

Moving the Snowball to `0d:00.3` removes both the VIA hub and the chipset controller.
The outages (8–19 min: 11:21:53 → 11:41:01, 11:43:02 → 11:51:15, no `xhci` errors)
look like the hub losing power, not a recoverable link error. VIA VL81x hubs have a
history of random resets on Linux
([Arch](https://bbs.archlinux.org/viewtopic.php?id=291592),
[raspberrypi/linux#4114](https://github.com/raspberrypi/linux/issues/4114)).

**Verdict: try this first**, before a rear port.

## 2. The EasyEffects watchdog

### The premise holds in 8.2.8

8.2.8 is the newest tag. In `src/echo_canceller.cpp`:

```cpp
void EchoCanceller::clear_data() {
  if (lv2_wrapper == nullptr) {
    return;                       // <- webrtc canceller: always taken
  }
  ...
  setup();                        // <- so init_webrtc() is never reached
}
```

The UI reset can't clear WebRTC state; rebuilding the instance is the only route.

### "Reference moved" is redundant

Upstream [d4665ddf](https://github.com/wwmm/easyeffects/commit/d4665ddf) (2026-05-20)
relinks the mic pipeline when the output changes and links mono channels to both
probe channels; `26e2723f` improved probe ports. Both are in 8.2.8 (`compare` shows
`behind_by=0`), closing [#5095](https://github.com/wwmm/easyeffects/issues/5095). The
watchdog's `reference moved` branch misfires on unrelated churn (11:51:18, 3 s after
the hub re-enumerated). The mono fix would have explained a doubled voice on the mono
Snowball (`S16LE 1 48000`), but it's already installed, so it's ruled out.

**Verdict:** soften or drop the probe-change trigger; keep sink-resumed.

### The doubled voice is likely DeepFilterNet

[easyeffects#3851](https://github.com/wwmm/easyeffects/issues/3851): DFN latency
accumulates under CPU load and never recovers: ~15 ms baseline, ~55 ms with DFN,
**100 ms+ after load**, and toggling the plugin returns to 100 ms+. The maintainer: the
only way is "destroying the whole plugin instance and recreating it … **jumps in audio
level as well as noises can happen**", a warning about `easyeffects-aec-reset`'s path.

The load dependence fits DFN, and the preset swap already rebuilds DFN with the
canceller. **Not confirmed here**: zero `Underrun detected (RTF: …)` lines this boot,
but EE 8.x's native DFN may not log them. Settle it by measuring input latency before
and after sustained load (needs the mic to stay connected).

### Realtime scheduling is fine

[pipewire#4748](https://gitlab.freedesktop.org/pipewire/pipewire/-/issues/4748) (portal
blocking RT) doesn't apply: easyeffects, pipewire, wireplumber and pipewire-pulse
`data-loop.0` threads all run `SCHED_RR` 20 with rtkit. Xruns under load are real CPU
starvation, so raising the xrun threshold is correct.

### Graph tuning

Live on both sinks: `api.alsa.headroom=1024`, `session.suspend-timeout-seconds=0`.
`node.latency = 512/48000` + `node.lock-quantum` doesn't give a 512 graph: the mic is a
follower, observed at 1024 with the sink driving 2048. That's fine; the usual advice for
EasyEffects crackling under load is `min-quantum` 1024
([Mint](https://forums.linuxmint.com/viewtopic.php?t=450701)). The watchdog's
`ee_state` jq degrades to `none\tnone\tnone\t0` when the canceller is absent.

## Takeaways

1. Move the Snowball to `0d:00.3` (bus 5/6, CPU-attached, empty). Free.
2. Update BIOS 4805 → 5031 (AGESA 1.2.0.E).
3. Drop `usbcore.autosuspend=-1` as a fix.
4. Keep the reset mechanism.
5. Gate the xrun trigger on `consumers -eq 0`, raise `XRUN_THRESHOLD` well above 3,
   soften the probe-change trigger.
6. Treat the reset as a DeepFilterNet delay flush as much as an AEC reset.
7. Fix the `hosts/local/audio.nix` comment: the graph runs at 1024, not 512.
