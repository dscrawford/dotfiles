# Steam I/O stutter on this machine: what is real, what is inert, what is ruled out

*Generated: 2026-09-20 | Sources: 34 | Confidence: High on the local measurements and the two config defects; Medium on which mechanism actually causes the freezes, because no freeze has been captured yet*

Companion to `docs/steam-ui-performance-research.md` (2026-08-04, compositor-side)
and `docs/memory-pressure-research.md` (2026-09-18, memory-side). This one covers
I/O and the storage/VRAM path, and it inherits the memory doc's central finding:
every graphical process lives in one cgroup, and that breaks more than memory.

---

## Executive summary

**Disk I/O is not what freezes this desktop.** Measured directly: a 109 GB Steam
library move drove `io.pressure full` to 70% of wall time — every task blocked —
while sway's IPC round-trip stayed at **2 ms across 268 samples, max 4 ms**. The
compositor does not flinch under I/O starvation on this hardware.

Two real defects were found, both verified on the running system, neither of them
the I/O contention that was being hunted:

1. **The NVIDIA shader disk cache is sitting on its ceiling.** 1000.5 MiB against
   a 1024 MiB default. NVIDIA's documented behaviour at the limit is to **wipe**
   the cache, and Steam issue #11392 documents exactly this producing continuous
   in-game shader recompilation and 100% CPU. `__GL_SHADER_DISK_CACHE_SIZE` is
   set nowhere in this config. This is the highest-value finding: precondition
   confirmed locally, fix is one environment variable.

2. **Every I/O priority knob in `priority.nix` is inert**, for two independent
   reasons — the weights are on the wrong cgroup branch, *and* `io.weight` has no
   controller behind it on this machine. Fixing either one alone changes nothing.

A third item is a live risk rather than a defect: **VRAM headroom is ~1.5 GB**
with a game running, and roughly 1.4 GB of the card is held by sway, Firefox and
Steam's own CEF before the game starts.

---

## 1. What the live system shows

Measured 2026-09-20, kernel 6.18.44, NVIDIA 610.57.04, RTX 3080 Ti, ext4 on two
NVMe drives, sway 1.12 / wlroots 0.20.2.

| Fact | Value |
|---|---|
| sway IPC round-trip under `io_full` 70% | **min 2 / p50 2 / p99 3 / max 4 ms** (268 samples) |
| `io.pressure full` during a 109 GB library move | p50 447, p99 1307, max 2032 ms per sample |
| Dirty pages at peak | 8.9 GB |
| `~/.cache/nvidia/GLCache` | **1,049,052,918 B = 1000.5 MiB** / 576 files / oldest 2023-09-10 |
| NVIDIA default cache cap | **1024 MiB** (raised from 128 MiB in driver 460) |
| `__GL_SHADER_DISK_CACHE_SIZE` | **unset** — absent from the flake and from Steam's environ |
| VRAM, game running | 10,083–10,431 MiB used of 12,288; **1,474–1,822 MiB free** |
| VRAM held by non-game processes | sway 536, steamwebhelper 465 + 96, Firefox 262–427, Xwayland 4 |
| BAR1 | 10,284 MiB used of 16,384 |
| I/O scheduler, both NVMe | `[none]` — mq-deadline, kyber available; BFQ built as a module, **not loaded** |
| `io.cost.model` / `io.cost.qos` | **empty — iocost disabled** |
| `wbt_lat_usec` | 2000 (writeback throttling active) |
| `read_ahead_kb` / `nr_requests` | 128 / 1023 |
| Mount options, both filesystems | `rw,relatime` (no `discard`, no `noatime`) |
| Kernel support | `IOCOST=y IOLATENCY=y IOPRIO=y BLK_DEV_THROTTLING=y` |
| `session-3.scope` (sway, Xwayland, Steam, Firefox) | io.weight **100**, cpu.weight **100**, memory.low **0** |
| `user@1000.service/session.slice` (where `priority.nix` aims) | io.weight 1000, cpu.weight 1000, memory.low 512M |
| Outputs | 2560x1440@164.958, 3440x1440@164.900, 3840x2160@59.997 — mixed refresh |

---

## 2. The shader cache is on its ceiling

`~/.cache/nvidia/GLCache` measures 1000.5 MiB. The NVIDIA default is 1024 MiB,
raised from 128 MiB in the 460 driver, per the driver release notes cited in
[Steam issue #11392](https://github.com/ValveSoftware/steam-for-linux/issues/11392).
The cache holds 576 files spanning 2023-09-10 to today — a long-lived cache that
has now reached the cap and cannot grow.

NVIDIA's own OpenGL environment-variable documentation describes the behaviour at
the limit as a wipe, not a prune:

> If the default cache is used and `__GL_SHADER_DISK_CACHE_SIZE` is set locally:
> any applications that subsequently run without setting it will revert the cache
> to the default size and **cause the cache to be wiped if it now goes over**.
>
> — [NVIDIA driver README, OpenGL environment variables](https://download.nvidia.com/XFree86/Linux-x86_64/580.95.05/README/openglenvvariables.html)

Issue #11392 (opened 2024-10-27, still open, no Valve or NVIDIA response) reports
the downstream effect: the driver prunes Fossilize-primed shaders, games
recompile continuously mid-session, CPU pegs at 100%, and one reporter had Discord
audio degrade from the CPU exhaustion. The reporter's fix was
`__GL_SHADER_DISK_CACHE_SIZE=10737418240` (10 GB) in Steam launch options; their
cache then grew to 4.3–5.7 GB and the stutter stopped.

**Confidence.** High that the precondition holds here — the cache size was
measured, the cap is documented, the variable is provably unset. Medium that it
is the cause of the freezes being investigated: #11392 is a single report, albeit
one with controlled before/after evidence, and it describes *in-game* stutter
rather than Steam-client-UI freezes. It is cheap to test and cannot make anything
worse, which is why it leads the recommendations.

**Interaction with Fossilize.** Steam's shader pre-caching writes into
`steamapps/shadercache` (1.2 GB + 2.2 GB across the two libraries here); the
driver's own GLCache is separate and is the one at the cap. Priming shaders into
a cache the driver then wipes is the specific failure mode #11392 describes — so
on this machine the two interact badly, and raising the cap is strictly better
than disabling pre-caching.

---

## 3. Every I/O priority knob in `priority.nix` is inert

Two independent reasons. Both must be fixed for either to matter.

### 3.1 The weights are on the wrong branch

`priority.nix` sets `CPUWeight`/`IOWeight` 1000 on `systemd.user.slices.session`.
That lands on `/user.slice/user-1000.slice/user@1000.service/session.slice`, which
holds the user manager's services — PipeWire, dbus-broker, the portals. Measured
there: io.weight 1000, cpu.weight 1000, memory.low 512M. Working as intended.

But sway, Xwayland, Steam and Firefox are all in
`/user.slice/user-1000.slice/session-3.scope`, the logind session scope, measured
at io.weight **100**, cpu.weight **100**, memory.low **0**. The desktop, the game
and the Steam client all run at default priority with zero protection.

This is the I/O analogue of the memory defect already documented in
`docs/memory-pressure-research.md` §2 and §4.2 — same cgroup, same cause (sway
`exec`s its children rather than launching them as systemd user units), same
ancestor-chain break at `user-1000.slice`. The fix is the same fix.

### 3.2 `io.weight` has no controller behind it

Even on the correct cgroup, `io.weight` would do nothing here. The kernel
documentation is explicit that weight-based proportional distribution is provided
by the iocost cost-model controller or, where BFQ is the scheduler for a device,
by BFQ's own cgroup support
([Control Group v2 — kernel.org](https://docs.kernel.org/admin-guide/cgroup-v2.html)).
A 2026-08-10 patch to the cgroup-v2 docs restates this after the previous wording
went stale ([LKML](https://lkml.org/lkml/2026/8/10/261)).

On this machine both NVMe devices use `[none]`, BFQ is not loaded, and
`io.cost.model`/`io.cost.qos` are empty — iocost "is disabled by default and can
be enabled by setting 'enable' to 1". So writes to `io.weight`, including
everything systemd's `IOWeight=` emits, are silently discarded.

This is not a novel discovery; it bit someone else recently and their fix is
public. [secureblue-blue-build PR #28](https://github.com/fromelicks/secureblue-blue-build/pull/28)
(merged 2026-08-28) states it in as many words:

> NVMe defaults to the `none` scheduler where io.weight is inert, so every
> IOWeight= above would otherwise be silently ignored.

Their remedy was a dedicated systemd service enabling the `io.cost` controller,
plus `MemoryLow` applied along the **whole ancestor chain** — `user.slice`,
`user-.slice`, `user@.service` and `session.slice` — which is precisely the chain
break `memory-pressure-research.md` §4.2 found unrepaired here. Independent
confirmation that both halves of the diagnosis are real.

### 3.3 Which control to actually use

| Control | Scheduler-dependent? | Calibration needed? | systemd option |
|---|---|---|---|
| `io.weight` | **Yes** — needs iocost or BFQ | — | `IOWeight=` |
| `io.cost` | No (works with `none`) | **Yes, per device** | none (raw sysfs) |
| `io.latency` | **No** | No | `IODeviceLatencyTargetSec=` |
| `io.max` | **No** | No | `IOReadBandwidthMax=` etc. |

iocost is the most capable but needs a measured cost model per device. Meta's own
documentation — they wrote the controller — says generic parameters are not
enough:

> to achieve a reasonable level of control, configure the IO cost model in
> `/sys/fs/cgroup/io.cost.model` according to the specific device […] The cost
> model is of course an approximation of reality. It can't exactly predict how
> the hardware will behave.
>
> — [resctl-demo: IO cost parameters](https://facebookmicrosites.github.io/resctl-demo-website/docs/demo_docs/setting_benchmarks/iocost/)

Coefficients come from `tools/cgroup/iocost_coef_gen.py` in the kernel tree, which
benchmarks the device to derive them. Its cost-model limitations are still active
kernel work in 2026 ([BPF struct_ops cost model RFC](https://github.com/kernel-patches/bpf-rc/pull/9259)).

`io.latency` needs no calibration and no scheduler change: you give a cgroup a
latency target and the kernel throttles its *peers* when the target is missed.
systemd exposes it as `IODeviceLatencyTargetSec=`, confirmed in
`systemd.resource-control(5)` as installed here. Its limit is that it only acts
between siblings — protecting `user.slice` shields the desktop from `system.slice`
(nix-daemon and dockerd are both active here) but does nothing about Steam
starving itself, which is exactly what the 109 GB move did.

---

## 4. Leave the I/O scheduler alone

The obvious-looking move — switch to BFQ so `io.weight` starts working — is wrong
here twice over.

**Tail latency.** The peer-reviewed ICPE '24 study
[BFQ, Multiqueue-Deadline, or Kyber? Performance Characterization of Linux Storage Schedulers in the NVMe Era](https://dl.acm.org/doi/10.1145/3629526.3645053)
(May 2024) measured `none`, Kyber and mq-deadline reducing tab-switch P99 latency
by 29%, 35% and 18% respectively against BFQ, and found BFQ the most
CPU-intensive. Note: the exact percentages are from search summaries of the paper;
the ACM page and PDF could not be fetched directly, so treat the numbers as
second-hand and the direction as well-supported.

**It would disable the throttling already protecting us.** `wbt_lat_usec` is 2000
here — writeback throttling is live, and it exists specifically to stop background
buffered writeback from starving foreground I/O on blk-mq devices that have no
software scheduler ([LWN, 2016](https://lwn.net/Articles/704739/)). A 2022 kernel
patch disables WBT whenever BFQ is the elevator
([LKML](https://lkml.iu.edu/hypermail/linux/kernel/2209.2/01955.html)), because
BFQ has its own mechanism. So switching to BFQ trades a working, measured
protection for a worse-performing one. `none` + WBT stays.

---

## 5. VRAM headroom is thin

With Spider-Man 2 running: **10,083–10,431 MiB of 12,288 used, 1.5–1.8 GB free.**
Before the game even starts, sway (536 MiB), Steam's two CEF processes
(465 + 96 MiB) and Firefox (262–427 MiB) hold roughly 1.4 GB.

This machine already has a recorded history here — the saved note that VRAM
exhaustion on this card takes down the whole sway session, and
`docs/bar1-crash-research.md`. BAR1 is at 10,284 of 16,384 MiB.

Steam's own client is holding about half a gigabyte of VRAM while a game runs, and
`steam-ui-performance-research.md` §4.2 already recommended closing the Friends
list and chat windows for CPU reasons. The VRAM figure is a second, independent
reason to do the same thing.

**Confidence.** High on the measurements. Medium as an explanation of the
freezes — VRAM exhaustion on NVIDIA Linux causes eviction over PCIe and
hundreds-of-ms hitches, which fits "sporadic freeze while using Steam", but it was
not captured happening. The probe at `/tmp/freeze-probe/probe.sh` records GPU
memory per sample and will show it if it is the cause.

---

## 6. Ruled out, with the measurement that rules it out

Each of these is a plausible cause that the research surfaced and the machine then
contradicted. They are listed because *not* chasing them is worth as much as the
positive findings.

| Candidate | Why it is out |
|---|---|
| Disk I/O contention freezing the desktop | sway RTT 2 ms through `io_full` 70%, 268 samples |
| `appinfo.vdf` async-write stutter ([community report](https://steamcommunity.com/groups/SteamClientBeta/discussions/0/3805028278534072792/)) | Measured here: **28–49 ms**, 5 writes/session, 1512 apps / 4.5 MB. Real elsewhere with huge libraries; not this machine |
| Fossilize background shader processing ([#7443](https://github.com/ValveSoftware/steam-for-linux/issues/7443)) | No `fossilize_replay` processes; shadercache sizes static |
| Steam `UpdatesJob` spin loop | 19,929 iterations found — but **all on 2026-09-18, 17:05–17:42** at ~450/min. Zero today. A real 40-minute pathological episode, not an ongoing cause |
| Chromium display re-enumeration storm | 585 events in `webhelper_gpu.txt` = 3 per launch across 195 launches since Aug 28. Normal |
| Memory pressure / swap thrash | Memory PSI 0.33 s total since boot; 0 B of 35 GB swap used |
| Kernel or hardware stall | Zero `hung task`, `blocked for more than`, nvme timeout/reset, `EXT4-fs error`, or Xid entries this boot or last |
| CEF software-rendering fallback | Ruled out in `steam-ui-performance-research.md` §1.1; still holds |
| Mixed-refresh GPU power-state pinning | **Not testable yet** — see §8. The GPU was legitimately busy (86% util, game running) every time it was sampled |

---

## 7. The strongest external lead, and the trap attached to it

[Issue #10806](https://github.com/ValveSoftware/steam-for-linux/issues/10806)
("Steam redraw problem in tiling WMs") and its duplicate
[#11056](https://github.com/ValveSoftware/steam-for-linux/issues/11056)
(2024-07-01) describe the Steam UI freezing visually — clicks and scroll register,
nothing repaints — until the window is moved or resized, often after exiting a
game or switching workspaces. Multiple independent reporters; no Valve root-cause
statement. sway is a tiling WM and this is the closest published match to the
reported symptom, including the part where the rest of the desktop stays fine.

The circulated workaround is to disable **Settings → Interface → GPU accelerated
rendering in web views**. Do not apply it here without weighing the cost:

- `steam-ui-performance-research.md` §4.1 already concluded, from three
  independent local checks, that CEF is GPU-accelerated on this machine and that
  disabling it would be an active downgrade.
- [Issue #13151](https://github.com/ValveSoftware/steam-for-linux/issues/13151)
  (2026-05-03) reports that with it off on NVIDIA + Wayland, Big Picture runs at
  about 1 fps.

So the fix for the redraw freeze is the cause of a worse problem in Big Picture.
If the freeze turns out to be #10806, the honest options are to live with the
resize workaround, or move Big Picture to the gamescope session as
`steam-ui-performance-research.md` §4.3 recommends, and keep web-view
acceleration on.

---

## 8. Untested: mixed-refresh GPU clock behaviour

This config runs 3840x2160@59.997 alongside two 165 Hz outputs. There is
cross-corroborated community evidence that mixed-refresh multi-monitor NVIDIA
setups pin the GPU at maximum power state at idle — several posters in
[this NVIDIA forum thread](https://forums.developer.nvidia.com/t/gpu-is-stuck-to-maximun-power-state-at-idle-when-using-multiple-monitors/310924)
match specific refresh-rate combinations (144+60 pins, 144+75 does not), with an
NVIDIA-internal bug number cited that cannot be verified publicly. Separately,
[open-gpu-kernel-modules #1251](https://github.com/NVIDIA/open-gpu-kernel-modules/issues/1251)
(2026-07-20, open) reports driver **610.43.03** — one release below the 610.57.04
installed here — sticking at P8 with memory clock pinned at 405 MHz during Wayland
compositing, causing "intermittent desktop stutter at steady FPS."

That NVIDIA considers the underlying multi-monitor clock management a real problem
is corroborated by driver 615.71.09 (2026-09) adding an opt-in
`RmDisableDisplayGlitchPerfLimit=1` registry token, documented as trading idle
power for a risk of "momentary display glitches" in multi-monitor setups
([GamingOnLinux](https://www.gamingonlinux.com/2026/09/nvidia-driver-615-71-09-released-for-linux-with-vulkan-proton-improvements-with-nvidia-reflex/)).
That token is not available on 610.57.04.

**This could not be tested.** Every GPU sample taken was with a game running
(86% utilisation, 258 W, memory clock at its 9501 MHz maximum), which is correct
behaviour and says nothing about idle. Testing requires sampling
`nvidia-smi --query-gpu=pstate,clocks.mem,power.draw` with the desktop idle and no
game, then repeating with the 4K@60 output disabled. Until then this is a lead,
not a diagnosis.

---

## 9. Recommended changes, in order

Not applied. Items 1 and 2 are independent of the unresolved diagnosis and are
worth doing regardless; 3 onward should wait for a captured freeze.

**1 — Raise the NVIDIA shader cache cap.** The one change with a confirmed local
precondition, no downside, and a documented mechanism. Global, so it applies to
every Vulkan/OpenGL client rather than per-game launch options:

```nix
# shared/gaming.nix or hosts/local/steam.nix
environment.sessionVariables.__GL_SHADER_DISK_CACHE_SIZE = "10737418240";  # 10 GiB
```

Verify after a rebuild and relogin that `~/.cache/nvidia/GLCache` grows past
1024 MiB. If it stays pinned at ~1000 MiB, the variable is not reaching the
driver — check it is present in the game's environ, not just the shell's, since
Steam runs games inside the FHS sandbox.

**2 — Repair the cgroup chain and stop relying on `IOWeight`.** The `MemoryLow`
half is already Tier 1 in `memory-pressure-research.md`; this adds the I/O half
and the ancestor levels secureblue found necessary:

```nix
systemd.slices."user-" = {
  overrideStrategy = "asDropin";   # user-.slice is a template, not a real unit
  sliceConfig.MemoryLow = "2G";    # closes the break at user-1000.slice
};
```

Do **not** add `IOWeight=` anywhere expecting it to work. If I/O prioritisation is
wanted, either protect the desktop branch from `system.slice` background work with
a control that functions under `none`:

```nix
systemd.slices.user.sliceConfig.IODeviceLatencyTargetSec = "/dev/nvme1n1 50ms";
```

…or enable and calibrate iocost as secureblue did. `IODeviceLatencyTargetSec` is
the cheaper first move; note it only constrains siblings, so it will not help when
Steam is the thing saturating the disk.

**3 — Reclaim VRAM before blaming anything else.** Close the Friends list and chat
CEF windows while gaming — worth ~0.5 GB of a card with 1.5 GB spare, and already
recommended on CPU grounds in `steam-ui-performance-research.md` §4.2.

**4 — Keep the storage stack as it is.** Scheduler stays `none`; WBT stays on.
`noatime` on both filesystems is uncontested low-risk housekeeping but was not
found benchmarked against interactive latency, so it is cleanup, not a fix.

**5 — Revisit `vm.dirty_bytes`.** The caps added to `priority.nix` on 2026-09-20
(512 MiB background / 2 GiB hard) are mechanism-grounded — the ratio defaults are
a percentage of 62 GB and an 8.9 GB backlog was measured — but the specific
numbers are tuning-guide convention, not benchmark output. No 2024–2026 controlled
benchmark for these values on NVMe desktops was found. Keep them as a bound on
worst-case flush size; do not treat them as the freeze fix, since the flush they
bound demonstrably did not stall the compositor.

**6 — Leave `vm.swappiness = 150` alone, but know it is on shakier ground than it
looks.** It matches CachyOS and Pop!_OS defaults for zram. However LWN reported on
2026-03-05 that MGLRU — the reclaim path on this kernel generation — "does not
properly balance reclaim between anonymous and file-backed pages… the traditional
swappiness control knob does not fix the problem"
([Reconsidering the multi-generational LRU](https://lwn.net/Articles/1060967/)),
with fixes still landing through August 2026. The setting is not harmful; whether
it does what it is assumed to do is an open kernel question.

**7 — Do not reach for `sched_ext`/`scx_lavd` yet.** `services.scx.scheduler`
exists in nixpkgs and kernel 6.18 supports sched_ext, and `scx_lavd` is explicitly
designed for gaming latency. But **no quantified stutter benchmark for it was
found anywhere** — CachyOS's own wiki declines to cite numbers and tells you to
measure yourself. There is also an open EPERM attach failure for `scx_lavd` on a
nearby kernel ([scx#3413](https://github.com/sched-ext/scx/issues/3413)). It is a
large change with no evidence behind it for this specific symptom.

**Verification.** `/tmp/freeze-probe/probe.sh` samples sway IPC round-trip, PSI
deltas, dirty pages, D-state count, Steam's renderer process state and GPU memory
at 1 Hz, and flags compositor stalls and blocked-renderer moments into
`events.log`. The three outcomes that discriminate between everything above:

- sway RTT spikes with the freeze → compositor or driver, §8 territory.
- sway RTT flat, Steam renderer in `D` → Steam blocked on I/O, §3 territory.
- sway RTT flat, renderer in `R` or `S`, `events.log` empty → CEF-internal, §7.

---

## Gaps

- **No freeze has been captured.** Every mechanism above is either ruled out by
  measurement or supported by a precondition, not by observation of the actual
  symptom. The probe exists to close this.
- **Whole-desktop vs Steam-window-only is still unknown**, and it halves the
  search space. It was asked and not yet answered.
- **§8 is untestable while a game runs** and needs a deliberate idle measurement.
- The ICPE '24 percentages are second-hand; the primary PDF would not fetch.
- Steam issue #11392's 1 GiB default traces to NVIDIA release notes quoted in the
  issue, not to a page fetched directly — though the local cache sitting at
  1000.5 MiB is strong independent corroboration of a ~1 GiB cap.
- Agent research surfaced a substantial volume of AI-generated SEO content with
  confident, unsourced sysctl values. None of it was used. Where this report gives
  a number, it comes from kernel docs, a kernel patch, a peer-reviewed paper, a
  named upstream issue, or a measurement on this machine.

---

## Sources

1. [Steam issue #11392 — NVIDIA driver prunes precompiled shaders, cold-cache stutter](https://github.com/ValveSoftware/steam-for-linux/issues/11392) — the shader cache cap, symptom and workaround.
2. [NVIDIA driver README — OpenGL environment variables](https://download.nvidia.com/XFree86/Linux-x86_64/580.95.05/README/openglenvvariables.html) — cache is wiped, not pruned, when over size.
3. [Control Group v2 — kernel.org](https://docs.kernel.org/admin-guide/cgroup-v2.html) — io.weight needs iocost or BFQ; io.latency and io.max semantics; iocost disabled by default.
4. [LKML 2026-08-10 — docs: cgroup-v2: fix stale "io" controller wording](https://lkml.org/lkml/2026/8/10/261) — restates the controller dependency.
5. [secureblue-blue-build PR #28 — keep the desktop responsive under load](https://github.com/fromelicks/secureblue-blue-build/pull/28) — merged 2026-08-28; same two defects, public fix.
6. [resctl-demo — IO cost parameters](https://facebookmicrosites.github.io/resctl-demo-website/docs/demo_docs/setting_benchmarks/iocost/) — iocost needs a per-device model.
7. [ICPE '24 — BFQ, Multiqueue-Deadline, or Kyber?](https://dl.acm.org/doi/10.1145/3629526.3645053) — NVMe scheduler tail-latency benchmark.
8. [LWN — block: buffered writeback throttling](https://lwn.net/Articles/704739/) — what WBT is for.
9. [LKML — blk-wbt: don't enable throttling if default elevator is bfq](https://lkml.iu.edu/hypermail/linux/kernel/2209.2/01955.html) — BFQ disables WBT.
10. [Steam issue #10806 — redraw problem in tiling WMs](https://github.com/ValveSoftware/steam-for-linux/issues/10806) and [#11056](https://github.com/ValveSoftware/steam-for-linux/issues/11056) — closest published symptom match.
11. [Steam issue #13151 — GPU accelerated web views off ⇒ Big Picture ~1 fps](https://github.com/ValveSoftware/steam-for-linux/issues/13151) — the trap on #10806's workaround.
12. [Steam issue #7443 — fossilize_replay on every start](https://github.com/ValveSoftware/steam-for-linux/issues/7443) — shader pre-caching CPU cost.
13. [Steam Client Beta — writing appinfo.vdf causes stutter](https://steamcommunity.com/groups/SteamClientBeta/discussions/0/3805028278534072792/) — real elsewhere, not here.
14. [NVIDIA forums — GPU stuck at maximum power state with multiple monitors](https://forums.developer.nvidia.com/t/gpu-is-stuck-to-maximun-power-state-at-idle-when-using-multiple-monitors/310924) — mixed-refresh pinning reports.
15. [open-gpu-kernel-modules #1251 — P8 stuck, 405 MHz memory clock, Wayland compositing](https://github.com/NVIDIA/open-gpu-kernel-modules/issues/1251) — driver 610.43.03.
16. [GamingOnLinux — NVIDIA 615.71.09 adds RmDisableDisplayGlitchPerfLimit](https://www.gamingonlinux.com/2026/09/nvidia-driver-615-71-09-released-for-linux-with-vulkan-proton-improvements-with-nvidia-reflex/) — NVIDIA acknowledging multi-monitor clock glitches.
17. [LWN — Reconsidering the multi-generational LRU](https://lwn.net/Articles/1060967/) — MGLRU vs swappiness, 2026-03-05.
18. [Documentation for /proc/sys/vm](https://docs.kernel.org/admin-guide/sysctl/vm.html) — dirty ratio/bytes semantics.
19. [sched-ext issue #3413 — scx_lavd EPERM attach failure](https://github.com/sched-ext/scx/issues/3413).
20. [CachyOS wiki — sched-ext tutorial](https://wiki.cachyos.org/configuration/sched-ext/) — scx_lavd design intent, no benchmark numbers.
21. [NixOS wiki — Steam](https://wiki.nixos.org/wiki/Steam) — gamescope/enableWsi/capSysNice patterns.
22. [gamescope issue #1592 — WSI layer presentation hangs on NVIDIA](https://github.com/ValveSoftware/gamescope/issues/1592).
23. [Phoronix — Steam Beta fixes UI scaling on XWayland](https://www.phoronix.com/news/Steam-Beta-31-July-2025) — 2025-07-31 changelog.
24. [Phoronix — MQ-Deadline optimized for better scalability](https://www.phoronix.com/news/MQ-Deadline-Scalability) — 2024-01 Axboe patches.
25. [BFQ — kernel.org](https://docs.kernel.org/block/bfq-iosched.html) — BFQ's stated interactivity design goal.

Local evidence — `/proc/pressure/*`, `/sys/fs/cgroup/**`, `/sys/block/nvme*/queue/*`,
`nvidia-smi`, `swaymsg -t get_outputs`, `~/.local/share/Steam/logs/*`,
`~/.cache/nvidia/GLCache`, `systemd.resource-control(5)` as installed,
`/proc/config.gz`, and 268 samples from `/tmp/freeze-probe/`.

---

## Methodology

Three parallel research agents (Steam client-side I/O; kernel and block-layer
latency tuning; NixOS/NVIDIA gaming config), restricted to built-in WebSearch and
WebFetch to avoid rate-limiting the shared scrapers. The main session handled
cross-checks via the open-websearch MCP and direct WebFetch of primary sources,
and did all local measurement.

Every claim about this machine was verified against the running system rather than
inferred from the sources — which is what eliminated four of the agents' leading
candidates (appinfo.vdf, Fossilize, the display re-enumeration storm, and I/O
contention as a desktop-freeze mechanism) and what promoted the shader cache from
a single-source issue report to the top recommendation.

Sub-questions investigated:
1. What in Steam's own I/O behaviour is documented to cause UI freezes?
2. What kernel/block-layer controls keep a desktop responsive under write load?
3. What do current NixOS gaming configs set, and is any of it evidence-backed?
4. Which of the above applies to this machine's measured state?
5. What does the machine contradict outright?
