# NVIDIA hard-lock during stream + camera: BAR1 aperture exhaustion

*2026-08-23. 12 sources. High confidence: the local crash trace matches the upstream
signature exactly.*

## Summary

Not a camera fault: **PCIe BAR1 aperture exhaustion** on the RTX 3080 Ti. BAR1 is
**256 MiB** and below 4 GiB, so *Above 4G Decoding / Resizable BAR is off in BIOS*;
the card supports up to **16 GiB**. With OBS (capture, camera upload, NVENC),
v4l2loopback and Discord's Chromium GPU process (screen share, camera preview) all
mapping buffers, the aperture fills. `nvidia_drm` issues a mapping past BAR1's end, the
PCI resource check rejects it, and the GPU's MMU fault cascades into a context-switch
timeout. The RM lock deadlocks, so `nvidia-smi`, VT switch and `systemctl reboot` hang.
The camera is the last straw.

## 1. Local evidence

`journalctl -b -2`, 2026-08-22:

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

| Region | Range | Size |
|---|---|---|
| BAR1 | `0xd0000000`–`0xdfffffff` | 256 MiB |
| BAR3 | `0xe0000000`–`0xe1ffffff` | 32 MiB |
| **Failed request** | `0xdfed0000`–`0xe003ffff` | starts 1.25 MiB before BAR1's end, runs **256 KiB into BAR3** |

`/var/log/gpu-monitor/2026-08-22.log`:

```
19:56:51  61C, 113.61 W,   1 %,  2374 MiB   <- normal
19:57:01  63C, 147.43 W, 100 %,  2617 MiB   <- wedged
19:58:19  56C,  21.81 W,   0 %,    33 MiB   <- next boot
```

Only **2.6 of 12 GiB VRAM** was used: address space ran out, not VRAM. The next boot
reports `reset pin BP_SYS_RST_L was tripped` (the reset button).

## 2. Known upstream bug

[open-gpu-kernel-modules#1134](https://github.com/NVIDIA/open-gpu-kernel-modules/issues/1134)
(open, 2026-05-07): same caller, same cascade, triggered by a Chromium renderer starting
(Discord is Chromium). From the thread:

- RTX 3090 Ti (same GA102): 256 MiB BAR1, ~940 MiB of 24 GB VRAM used when it dies.
- RTX 4090: BAR1 at 234/256 MiB with ~19 GiB VRAM free, 3/3 sessions; after Above 4G +
  ReBAR, BAR1 was 32 GiB and the load peaked at 8.4 GiB with no errors.
- **610.x looks like a regression**: a month on 595.71.05 without it, then freezes every
  day or two on 610.43.02; another reporter saw the same. We were on **610.57.04**.
- Mappings leak from the browser GPU process and are freed when it exits (104 → 41 MiB).
- ReBAR raises the ceiling, not the leak: a Blackwell card locked with 16 GiB BAR1. At
  256 MiB on Ampere it's trivially reachable, so ReBAR is still the biggest win.

Xid 109 / GSP-timeout on Wayland: [#1080](https://github.com/NVIDIA/open-gpu-kernel-modules/issues/1080),
[Xid guide](https://www.abhik.ai/articles/nvidia-xid-errors).

## 3. Why the camera

Idle BAR1 is **36 / 256 MiB**. Streaming with camera adds OBS screen capture (dmabuf
per frame via the portal), OBS camera, NVENC surfaces, v4l2loopback (`/dev/video10`),
Discord's GPU process, and sway's scanout buffers, each holding BAR1 mappings
(attribution inferred; exhaustion is in the log). Camera tips it over 256 MiB.

## 4. Changes, ranked

**1. BIOS (root cause).** ASUS TUF GAMING X570-PLUS, BIOS 4805
([guide](https://edgeup.asus.com/2021/guide-how-to-enable-resizable-bar-on-your-asus-powered-gaming-pc/)):

```
Advanced -> PCI Subsystem Settings
  Above 4G Decoding    -> Enabled
  Re-Size BAR Support  -> Enabled
```

`resource1_resize` = `0x7fc0`: 64 MiB … **16 GiB**, ~64x headroom. Verify:

```bash
nvidia-smi -q -d MEMORY | grep -A3 BAR1
```

**2. Driver branch.** `production` (595.x), the branch reporters ran clean. (Now set in
`hosts/local/nvidia.nix`.)

**3. Make a hang recoverable.** *(Revised 2026-08-24; see
[watchdog-sysrq-research.md](./watchdog-sysrq-research.md).)* `kernel.sysrq = 16`
allows only `sync`, so REISUB was never tested. #1289 and #1063 reporters recovered via
SysRq `s`/`u`/`b`.

```nix
boot.kernel.sysctl."kernel.sysrq" = 244;   # R-E-I-S-U-B, no memory dumps (bit 8 off)
systemd.settings.Manager.RebootWatchdogSec = "1min";  # default 10min
```

**Don't enable `RuntimeWatchdogSec`**: in this failure the kernel and PID 1 stay alive
(#1134: SSH responsive while `systemctl reboot` hung in `nvidia_drm` teardown), so the
watchdog keeps being petted. No report shows a hardware watchdog recovering an NVIDIA
hang, and this board has no pretimeout governor.

**Recovery today:** over SSH, `echo s | sudo tee /proc/sysrq-trigger`, then `u`, then
`b`. `/proc/sysrq-trigger` ignores the sysctl mask.

**4. Early warning.** `hosts/local/gpu-monitor.nix` doesn't log BAR1 used, the one
leading indicator; add a `nvidia-smi -q -d MEMORY` sample.

**5. Fewer GPU clients.** Discord already has `--disable-gpu-rasterization`
(`shared/home/packages.nix`). Then: camera only via OBS → v4l2loopback (Discord picks
`/dev/video10`); `kill $(pgrep -f 'discord.*--type=gpu-process')` before (never during)
a call; `--disable-gpu` on Discord (loses VA-API).

**Not yet:**
- `NVreg_EnableResizableBar=1` (currently 0): only after Above 4G is on, if BAR1 doesn't
  grow.
- `NVreg_EnableGpuFirmware=0` (GSP off) helps some Xid 109 cases
  ([ArchWiki](https://wiki.archlinux.org/title/NVIDIA)); large change, reserve.
- `resource1_resize` without BIOS support: the driver doesn't request the resize and
  Linux can't move adjacent BARs ([#579](https://github.com/NVIDIA/open-gpu-kernel-modules/discussions/579)).

Gap: BAR1 during a live stream + camera wasn't measured (risks another lock); the
BAR1 logging in step 4 closes it safely.
