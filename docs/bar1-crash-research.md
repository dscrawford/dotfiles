# NVIDIA hard-lock during stream + camera: BAR1 aperture exhaustion

*Generated: 2026-08-23 | Sources: 12 | Confidence: High (local crash trace matches upstream bug signature exactly)*

## Executive summary

The freeze is not a camera driver fault. It is **PCIe BAR1 aperture exhaustion** on
the RTX 3080 Ti. Your BAR1 window is **256 MiB** and sits **below the 4 GiB line**,
which means *Above 4G Decoding / Resizable BAR is disabled in BIOS*. The card
advertises BAR1 sizes up to **16 GiB**.

When enough GPU clients map display/video buffers at once — OBS (screen capture +
camera upload + NVENC), v4l2loopback, and Discord's Chromium GPU process with a
screen share and camera preview — the 256 MiB aperture fills. `nvidia_drm` then
issues a mapping that runs off the end of BAR1, the kernel's PCI resource check
rejects it, and the GPU takes an MMU fault that cascades into an unrecoverable
context-switch timeout. The RM lock deadlocks, so `nvidia-smi`, VT switch, and
`systemctl reboot` all hang — hence the reset button.

Adding the camera is what tips it over, which is why it "seems like the camera."
The camera is the last straw, not the cause.

## 1. The local evidence

From `journalctl -b -2`, Aug 22 2026:

```
19:56:53 kernel: resource: resource sanity check: requesting [mem 0xdfed0000-0xe003ffff],
                 which spans more than 0000:0b:00.0 [mem 0xd0000000-0xdfffffff 64bit pref]
19:56:53 kernel: caller __nv_drm_gem_nvkms_map+0xab/0x100 [nvidia_drm] mapping multiple BARs
19:56:53 kernel: [drm:__nv_drm_gem_nvkms_map [nvidia_drm]] *ERROR* Failed to map NvKmsKapiMemory
19:56:53 systemd-coredump: Process 14908 (.Discord-wrappe) terminated abnormally with signal 5/TRAP
19:57:01 kernel: NVRM: Xid 109, pid=2125, name=sway, errorString CTX SWITCH TIMEOUT, Info 0xdc005
19:57:01 kernel: NVRM: Xid 31, pid=14863, name=.Discord-wrappe, MMU Fault: ENGINE GRAPHICS GPC1
19:57:01 kernel: NVRM: Xid 31, pid=2597, name=Renderer, MMU Fault: ENGINE GRAPHICS HUBCLIENT_FE
```

Decoding the first line:

| Region | Range | Size |
|---|---|---|
| BAR1 (the aperture) | `0xd0000000`–`0xdfffffff` | 256 MiB |
| BAR3 | `0xe0000000`–`0xe1ffffff` | 32 MiB |
| **The failed request** | `0xdfed0000`–`0xe003ffff` | starts 1.25 MiB before BAR1's end, runs **256 KiB past it into BAR3** |

The allocator had only ~1.25 MiB of contiguous BAR1 left and handed out a mapping
that overran into the next BAR. That is textbook aperture exhaustion.

Corroborating telemetry from `/var/log/gpu-monitor/2026-08-22.log`:

```
19:56:51  61C, 113.61 W,   1 %,  2374 MiB   <- normal
19:57:01  63C, 147.43 W, 100 %,  2617 MiB   <- wedged, GPU pinned at 100%
19:58:19  56C,  21.81 W,   0 %,    33 MiB   <- P8 idle: this is already the next boot
```

Note only **2.6 GiB of 12 GiB VRAM** was in use. VRAM was never the constraint —
it was BAR1 address space.

The following boot reports `Previous system reset reason [0x00010800]: system reset
pin BP_SYS_RST_L was tripped` — i.e. the physical reset button. Confirms nothing
softer worked.

## 2. This is a known upstream bug

[NVIDIA/open-gpu-kernel-modules#1134](https://github.com/NVIDIA/open-gpu-kernel-modules/issues/1134)
(open, filed 2026-05-07) is the same failure, same caller, same cascade:

> the kernel logged a `resource sanity check` warning naming `__nv_drm_gem_nvkms_map`
> as the caller of an mmap that "spans more than" the device's BAR1 region. The same
> instant, the GPU took an MMU fault (Xid 31)... neither `nvidia-smi` nor
> `systemctl reboot` could complete; recovery required a hardware power-cycle. The
> trigger workload was a Chromium-based browser starting a new renderer process.

Discord is Electron/Chromium, so "Chromium GPU process" is exactly your trigger.

Key details from that thread:

- **It is BAR1 VA space, not VRAM.** Reporter `sanity` (RTX 3090 Ti, GA102 — same
  generation as yours): *"BAR1 is 256 MiB (Resizable BAR off), and only ~940 MiB of
  the 24 GB VRAM is in use when it dies, so it's BAR1 VA space that runs out, not
  VRAM."* Matches your 2.6 GiB / 12 GiB.

- **Enabling ReBAR resolved it for one reporter.** `leoric-crown` (RTX 4090):
  *"With ReBAR off (BAR1 at 256 MiB)... `Failed to map NvKmsKapiMemory`...
  BAR1 at 234/256 MiB used with the game up, while ~19 GiB of VRAM sat free. This
  happened 3 out of 3 sessions. After enabling Above 4G Decoding + Resizable BAR,
  BAR1 became 32 GiB. The same load now peaks around 8.4 GiB of BAR1 with no new
  map errors and no new coredumps."*

- **610.x looks like a regression.** `sanity`: *"I ran 595.71.05 for about a month
  without hitting it, then within a few days of updating to 610.43.02 I started
  getting hard display freezes every day or two."* `diacodion` independently
  suspected the same 595→610 jump. You are on **610.57.04**.

- **The mappings leak from the browser GPU process** and are reclaimed when it
  exits — `sanity` reclaimed 104 MiB → 41 MiB by killing Chrome's GPU process.

- **Caveat, stated honestly:** ReBAR raises the ceiling; it does not fix the leak.
  `r4hx` hard-locked on a Blackwell card *with* a 16 GiB BAR1. On Ampere at 256 MiB
  you are in the trivially-reachable case, so the ceiling raise is still the
  highest-value change available to you.

The Xid 109 / GSP-timeout family is separately well documented on Wayland
compositors ([#1080](https://github.com/NVIDIA/open-gpu-kernel-modules/issues/1080),
[NVIDIA forums](https://forums.developer.nvidia.com/t/kde-plasma-wayland-and-x11-full-driver-crashes-hangs/359264),
[Xid field guide](https://www.abhik.ai/articles/nvidia-xid-errors)).

## 3. Why the camera specifically triggers it

Baseline BAR1 on your idle system right now is **36 MiB / 256 MiB**. A stream with
camera adds, concurrently:

1. OBS screen capture — dmabuf import per frame via xdg-desktop-portal-wlr
2. OBS camera capture — V4L2 frames staged through mapped GPU buffers
3. OBS NVENC encode surfaces
4. v4l2loopback virtual cam output (`/dev/video10`)
5. Discord's Chromium GPU process — screen share receive + camera preview
6. sway's own scanout buffers

Each is a distinct GPU client holding BAR1 mappings. *(The per-client attribution
here is inference from the mechanism; the aperture-exhaustion root cause is
directly evidenced by the log.)* Adding the camera pushes the total over 256 MiB,
which is why streaming alone survives and streaming + camera does not.

## 4. Recommended changes, ranked

### Tier 1 — fixes the root cause (BIOS, no Nix change)

Reboot into BIOS (ASUS TUF GAMING X570-PLUS, BIOS 4805 — has the option):

```
Advanced -> PCI Subsystem Settings
  Above 4G Decoding    -> Enabled
  Re-Size BAR Support  -> Enabled
```

Your card's ReBAR capability bitmap (`resource1_resize` = `0x7fc0`) advertises
64 MiB / 128 / 256 / 512 / 1 GiB / 2 / 4 / 8 / **16 GiB**. This takes you from
256 MiB to up to 16 GiB — roughly 64× headroom.

Verify after reboot:

```bash
nvidia-smi -q -d MEMORY | grep -A3 BAR1
# Total should read far more than 256 MiB
```

Ref: [ASUS Edge Up ReBAR guide](https://edgeup.asus.com/2021/guide-how-to-enable-resizable-bar-on-your-asus-powered-gaming-pc/)

### Tier 2 — driver branch

`hosts/local/nvidia.nix` currently pins `nvidiaPackages.latest` = **610.57.04**.
`production` = **595.91.07**, the branch multiple reporters ran without hitting
this. The file's own comment already anticipates this ("Drop to .production if
610.x misbehaves").

```nix
package = config.boot.kernelPackages.nvidiaPackages.production;
```

### Tier 3 — make a hang recoverable instead of a reset-button event

> **Revised 2026-08-24.** The watchdog half of this recommendation was wrong. See
> [watchdog-sysrq-research.md](./watchdog-sysrq-research.md) for the full evidence.

`kernel.sysrq = 16` — only `sync` is permitted, so five of the six REISUB keys are
disabled and print `This sysrq operation is disabled`. SysRq has therefore never
actually been tested on this machine. Reporters in #1289 and #1063 recovered from
this hang class via SysRq `s`/`u`/`b` where every software method deadlocked.

```nix
boot.kernel.sysctl."kernel.sysrq" = 244;   # exactly R-E-I-S-U-B, no memory dumps
systemd.settings.Manager.RebootWatchdogSec = "1min";  # default 10min is too slow
```

`244` rather than `1` deliberately excludes bit 8, which would let anyone at the
keyboard dump kernel task state, registers, and memory info to the console.

**Do not enable `RuntimeWatchdogSec`.** It resets the box only when PID 1 or the
kernel stops running. In this failure class the kernel stays alive — #1134 records
SSH remaining responsive throughout, while `systemctl reboot` hung at `nvidia_drm`
teardown — so systemd would keep petting the watchdog indefinitely. No report
anywhere describes a hardware watchdog recovering an NVIDIA GPU hang. This board
also exposes no pretimeout governor, so a false positive would leave no trace.

**Best available recovery, no config change needed:** `sshd` is already active
here. From another machine — `echo s | sudo tee /proc/sysrq-trigger`, then `u`,
then `b`. `/proc/sysrq-trigger` ignores the sysctl bitmask entirely, and `s`+`u`
flush and quiesce the filesystems first, making it strictly safer than the reset
button.

### Tier 4 — early warning

`hosts/local/gpu-monitor.nix` logs temp/power/VRAM but **not BAR1** — the one
number that actually predicts this crash. Add a second `nvidia-smi -q -d MEMORY`
sample for BAR1 used, so you can watch it climb toward the ceiling during a
stream and stop before it hits.

### Tier 5 — reduce concurrent GPU clients

Discord already runs with `--disable-gpu-rasterization`
(`shared/home/packages.nix:139`). Further options, in increasing severity:

- Route the camera **only** through OBS → v4l2loopback → Discord selects
  `/dev/video10`. Avoids Discord opening the physical camera as a second client.
- `sanity`'s reclaim trick: `kill $(pgrep -f 'discord.*--type=gpu-process')`
  before a call to reset BAR1 usage. Do **not** do this mid-call.
- `--disable-gpu` on Discord entirely (costs VA-API decode).

### Not recommended yet

- `NVreg_EnableResizableBar=1` — currently `EnableResizableBar: 0`. Only
  meaningful once Above 4G Decoding is on in firmware; enable it after Tier 1
  if BAR1 doesn't grow on its own.
- `NVreg_EnableGpuFirmware=0` (GSP disable) — possible on Ampere with the
  proprietary driver, and it does help some Xid 109 cases
  ([ArchWiki](https://wiki.archlinux.org/title/NVIDIA)), but it is a large
  behavioural change. Hold it in reserve if Tiers 1–2 don't hold.
- Kernel-side ReBAR via `resource1_resize` sysfs without BIOS support — the
  NVIDIA driver does not request the resize itself
  ([discussion #579](https://github.com/NVIDIA/open-gpu-kernel-modules/discussions/579)),
  and Linux cannot move adjacent BARs to make room. Your board has the BIOS
  option, so take the supported path.

## Key takeaways

1. Root cause is a 256 MiB BAR1 aperture with Above 4G Decoding off — directly
   evidenced by the overrun address range in your own kernel log.
2. The camera is the last straw, not the fault. Nothing is wrong with the NexiGo.
3. One BIOS toggle buys ~64× headroom. Do that first; it needs no Nix change.
4. 610.57.04 is plausibly a regression over the 595 production branch.
5. Enable SysRq (`244`) so the next hang costs a clean-ish reboot, not a reset
   button. Do *not* arm the runtime watchdog — it cannot fire for this bug.
6. Log BAR1 in gpu-monitor — it is the leading indicator.

## Sources

1. [NVIDIA/open-gpu-kernel-modules#1134](https://github.com/NVIDIA/open-gpu-kernel-modules/issues/1134) — the matching bug: `__nv_drm_gem_nvkms_map` overruns BAR1 → Xid 31 → lock; Chromium GPU process trigger; ReBAR mitigation confirmed by a reporter
2. [NVIDIA/open-gpu-kernel-modules#1080](https://github.com/NVIDIA/open-gpu-kernel-modules/issues/1080) — GSP heartbeat timeout → Xid 109 family
3. [NVIDIA/open-gpu-kernel-modules#1030](https://github.com/NVIDIA/open-gpu-kernel-modules/issues/1030) — Xid 31 MMU fault reports
4. [NVIDIA/open-gpu-kernel-modules discussion #579](https://github.com/NVIDIA/open-gpu-kernel-modules/discussions/579) — BAR1 size is not settable via module params
5. [Xid 109 CTX SWITCH TIMEOUT, driver 595.45 regression](https://forums.developer.nvidia.com/t/xid-109-ctx-switch-timeout-nvidia-driver-595-45-broken-forced-to-use-590-44-01-rtx5060ti-16gb/363963) — driver-branch regressions in this family
6. [KDE Plasma/Wayland full driver crashes/hangs](https://forums.developer.nvidia.com/t/kde-plasma-wayland-and-x11-full-driver-crashes-hangs/359264) — Wayland compositor hang reports
7. [The Complete NVIDIA Xid Error Field Guide](https://www.abhik.ai/articles/nvidia-xid-errors) — Xid 31 is near-always a software/mapping bug
8. [GPU Memory Allocation Bugs with NVIDIA on Linux and Wayland](https://nickjanetakis.com/blog/gpu-memory-allocation-bugs-with-nvidia-on-linux-and-wayland-adventures) — NVIDIA memory allocation instability on Wayland
9. [ASUS Edge Up: How to enable Resizable BAR](https://edgeup.asus.com/2021/guide-how-to-enable-resizable-bar-on-your-asus-powered-gaming-pc/) — Advanced → PCI Subsystem Settings on ASUS boards
10. [ArchWiki: NVIDIA](https://wiki.archlinux.org/title/NVIDIA) — `NVreg_EnableGpuFirmware=0` guidance
11. [Screen freezes on Wayland, nvidia-drm flip event timeout](https://forums.developer.nvidia.com/t/screen-freezes-on-wayland-with-error-nvidia-drm-gpu-id-0x00002d00-flip-event-timeout-on-head-1/318959) — related display-path failure
12. [OBS #11447: Laggy recording with NVIDIA on Wayland](https://github.com/obsproject/obs-studio/issues/11447) — OBS/NVIDIA/Wayland capture path issues

## Methodology

Local forensics first: 20 boots of `journalctl` scanned for Xid/DRM/USB faults,
`gpu-monitor` telemetry correlated to the crash second, PCI BAR layout and ReBAR
capability bitmap read from sysfs, driver/kernel/module params captured. Then 6
web queries across two engines plus direct GitHub API reads of the upstream issue
and all its comments.

Sub-questions: (1) what actually crashed, from local logs; (2) is the
`__nv_drm_gem_nvkms_map` signature known upstream; (3) is BAR1 the constraint on
this machine; (4) why does the camera specifically trigger it; (5) what mitigations
exist and which are reachable on this hardware.

Gap: no direct measurement of BAR1 usage *during* a live stream+camera session —
reproducing it means risking another hard lock. Tier 4 monitoring is the safe way
to close that gap.
