# Steam I/O stutter: what is real, what is inert, what is ruled out

*2026-09-20. 34 sources. High confidence on local measurements and the two config
defects; medium on which mechanism causes the freezes (none captured yet).*

Companion to `docs/memory-pressure-research.md`, whose central finding carries over: every
graphical process lives in one cgroup.

## Summary

**Disk I/O doesn't freeze this desktop.** A 109 GB Steam library move drove
`io.pressure full` to 70% of wall time while sway's IPC round-trip stayed at **2 ms
over 268 samples, max 4 ms**.

Two real defects:

1. **The NVIDIA shader cache sat at its ceiling**: 1000.5 MiB of a 1024 MiB default.
   NVIDIA wipes the cache over the limit, and Steam #11392 shows that causing continuous
   in-game recompilation at 100% CPU. `__GL_SHADER_DISK_CACHE_SIZE` was unset. (Now set
   to 10 GiB in `hosts/local/steam.nix`.)
2. **Every I/O priority knob in `priority.nix` is inert**: the weights are on the wrong
   cgroup branch, *and* `io.weight` has no controller here. Fixing one alone does nothing.

Live risk: **~1.5 GB VRAM headroom** in-game, with ~1.4 GB held by sway, Firefox and
Steam's CEF.

## 1. Live system

Kernel 6.18.44, NVIDIA 610.57.04, RTX 3080 Ti, ext4 on two NVMe, sway 1.12.

| Fact | Value |
|---|---|
| sway IPC RTT under `io_full` 70% | **min 2 / p50 2 / p99 3 / max 4 ms** (268 samples) |
| `io.pressure full`, 109 GB move | p50 447, p99 1307, max 2032 ms per sample |
| Dirty pages at peak | 8.9 GB |
| `~/.cache/nvidia/GLCache` | **1000.5 MiB**, 576 files, oldest 2023-09-10 |
| NVIDIA default cap | **1024 MiB** (128 MiB before driver 460) |
| VRAM in-game | 10,083–10,431 of 12,288 MiB; **1,474–1,822 free** |
| VRAM, non-game | sway 536, steamwebhelper 465 + 96, Firefox 262–427, Xwayland 4 |
| BAR1 | 10,284 of 16,384 MiB |
| I/O scheduler (both NVMe) | `[none]`; BFQ a module, **not loaded** |
| `io.cost.model` / `io.cost.qos` | **empty: iocost disabled** |
| `wbt_lat_usec` | 2000 (writeback throttling on) |
| `read_ahead_kb` / `nr_requests` | 128 / 1023 |
| Mounts | `rw,relatime` |
| Kernel | `IOCOST=y IOLATENCY=y IOPRIO=y BLK_DEV_THROTTLING=y` |
| `session-3.scope` (sway, Xwayland, Steam, Firefox) | io.weight **100**, cpu.weight **100**, memory.low **0** |
| `user@1000.service/session.slice` (`priority.nix` target) | io.weight 1000, cpu.weight 1000, memory.low 512M |
| Outputs | 2560x1440@164.958, 3440x1440@164.900, 3840x2160@59.997 |

## 2. Shader cache at its ceiling

The NVIDIA README: when over size, the cache is **wiped**
([OpenGL env vars](https://download.nvidia.com/XFree86/Linux-x86_64/580.95.05/README/openglenvvariables.html)).
[#11392](https://github.com/ValveSoftware/steam-for-linux/issues/11392) (open since
2024-10, no vendor response): the driver prunes Fossilize-primed shaders, games recompile
mid-session, CPU pegs, Discord audio degrades. The reporter's
`__GL_SHADER_DISK_CACHE_SIZE=10737418240` grew the cache to 4.3–5.7 GB and stopped it.

High confidence the precondition holds; medium that it's the freeze (one report, in-game
rather than client UI). Steam's `steamapps/shadercache` (1.2 + 2.2 GB) is separate;
priming into a cache the driver wipes is the failure, so raise the cap rather than
disable pre-caching.

## 3. `priority.nix` I/O knobs are inert

**Wrong branch.** `CPUWeight`/`IOWeight` 1000 land on
`user@1000.service/session.slice` (PipeWire, dbus, portals). sway, Xwayland, Steam and
Firefox are in `session-3.scope` at 100/100/0, since sway `exec`s its children. Same
break at `user-1000.slice` as `memory-pressure-research.md` §2/§4.2.

**No controller.** Proportional `io.weight` needs iocost or BFQ
([cgroup-v2](https://docs.kernel.org/admin-guide/cgroup-v2.html),
[LKML 2026-08-10](https://lkml.org/lkml/2026/8/10/261)). Here both NVMe use `none` and
iocost is off, so `IOWeight=` is silently discarded.
[secureblue PR #28](https://github.com/fromelicks/secureblue-blue-build/pull/28) hit the
same ("NVMe defaults to the `none` scheduler where io.weight is inert") and fixed it with
an io.cost service plus `MemoryLow` on the whole chain (`user.slice`, `user-.slice`,
`user@.service`, `session.slice`).

| Control | Needs scheduler? | Calibration? | systemd |
|---|---|---|---|
| `io.weight` | **yes** (iocost/BFQ) | — | `IOWeight=` |
| `io.cost` | no | **per device** | raw sysfs |
| `io.latency` | no | no | `IODeviceLatencyTargetSec=` |
| `io.max` | no | no | `IOReadBandwidthMax=` etc. |

iocost needs a measured per-device model (`tools/cgroup/iocost_coef_gen.py`;
[resctl-demo](https://facebookmicrosites.github.io/resctl-demo-website/docs/demo_docs/setting_benchmarks/iocost/)).
`io.latency` needs nothing but only throttles siblings: protecting `user.slice` shields
the desktop from `system.slice` (nix-daemon, dockerd), not from Steam itself.

## 4. Keep the `none` scheduler

- [ICPE '24](https://dl.acm.org/doi/10.1145/3629526.3645053): `none`, Kyber and
  mq-deadline cut tab-switch P99 by 29%, 35%, 18% vs BFQ, which is also the most
  CPU-heavy (numbers second-hand; direction well supported).
- BFQ disables WBT ([LKML](https://lkml.iu.edu/hypermail/linux/kernel/2209.2/01955.html)),
  which is live here and exists to stop writeback starving foreground I/O
  ([LWN](https://lwn.net/Articles/704739/)).

## 5. Thin VRAM headroom

In Spider-Man 2: 1.5–1.8 GB free; ~1.4 GB held before the game starts. VRAM exhaustion
on this card has taken down sway before (`docs/bar1-crash-research.md`). Steam's CEF
holds ~0.5 GB, a second reason to close Friends and chat. Fits "sporadic freeze"
(eviction over PCIe gives 100s-of-ms hitches) but wasn't captured;
`/tmp/freeze-probe/probe.sh` records GPU memory per sample.

## 6. Ruled out

| Candidate | Why out |
|---|---|
| Disk I/O freezing the desktop | sway RTT 2 ms through `io_full` 70% |
| `appinfo.vdf` write stutter ([report](https://steamcommunity.com/groups/SteamClientBeta/discussions/0/3805028278534072792/)) | **28–49 ms**, 5 writes/session, 1512 apps / 4.5 MB |
| Fossilize ([#7443](https://github.com/ValveSoftware/steam-for-linux/issues/7443)) | no `fossilize_replay`; shadercache static |
| Steam `UpdatesJob` spin | 19,929 iterations, **all 2026-09-18 17:05–17:42**; zero today |
| Chromium display re-enumeration | 585 events / 195 launches = 3 per launch, normal |
| Memory pressure | memory PSI 0.33 s since boot; 0 of 35 GB swap |
| Kernel/hardware stall | no hung task, nvme reset, `EXT4-fs error` or Xid this boot or last |
| CEF software fallback | still ruled out |
| Mixed-refresh power state | **untested** (§8) |

## 7. Closest external match, and its trap

[#10806](https://github.com/ValveSoftware/steam-for-linux/issues/10806) /
[#11056](https://github.com/ValveSoftware/steam-for-linux/issues/11056): in tiling WMs the
Steam UI stops repainting (input still registers) until moved or resized, often after a
game exits. The workaround, disabling GPU-accelerated web views, makes Big Picture ~1 fps
on NVIDIA + Wayland ([#13151](https://github.com/ValveSoftware/steam-for-linux/issues/13151)).
If it's #10806: live with resize, or use the gamescope session; keep acceleration on.

## 8. Untested: mixed-refresh GPU clocks

4K@60 alongside two 165 Hz outputs. Reports that mixed-refresh NVIDIA setups pin max
power at idle (144+60 pins, 144+75 doesn't)
([forum](https://forums.developer.nvidia.com/t/gpu-is-stuck-to-maximun-power-state-at-idle-when-using-multiple-monitors/310924));
[open-gpu-kernel-modules #1251](https://github.com/NVIDIA/open-gpu-kernel-modules/issues/1251):
610.43.03 stuck at P8, 405 MHz memory, "intermittent desktop stutter". 615.71.09 adds
`RmDisableDisplayGlitchPerfLimit=1` ([GOL](https://www.gamingonlinux.com/2026/09/nvidia-driver-615-71-09-released-for-linux-with-vulkan-proton-improvements-with-nvidia-reflex/)),
not on 610.57.04. All samples were in-game (86%, 258 W, 9501 MHz). Test idle with
`nvidia-smi --query-gpu=pstate,clocks.mem,power.draw`, then again with 4K@60 off.

## 9. Recommendations

1. **Raise the shader cache cap** (done: `__GL_SHADER_DISK_CACHE_SIZE = "10737418240"`).
   Check `~/.cache/nvidia/GLCache` grows past 1024 MiB; if not, check the game's environ
   (Steam's FHS sandbox).
2. **Fix the cgroup chain; stop relying on `IOWeight`.**

   ```nix
   systemd.slices."user-" = {
     overrideStrategy = "asDropin";   # template unit
     sliceConfig.MemoryLow = "2G";    # closes the break at user-1000.slice
   };
   systemd.slices.user.sliceConfig.IODeviceLatencyTargetSec = "/dev/nvme1n1 50ms";
   ```

   Or enable and calibrate iocost as secureblue did.
3. **Reclaim VRAM**: close Friends and chat while gaming (~0.5 GB).
4. **Keep the storage stack**: `none` + WBT. `noatime` is housekeeping, not a fix.
5. **`vm.dirty_bytes`** caps (512 MiB / 2 GiB) bound worst-case flush; values are
   convention, not benchmarked, and the flush didn't stall the compositor anyway.
6. **`vm.swappiness = 150`** matches CachyOS/Pop!_OS for zram, but MGLRU doesn't balance
   anon vs file reclaim and swappiness doesn't fix it
   ([LWN 2026-03](https://lwn.net/Articles/1060967/)).
7. **Skip `scx_lavd`**: no quantified stutter benchmark anywhere, and an open EPERM attach
   bug ([scx#3413](https://github.com/sched-ext/scx/issues/3413)).

The 1 Hz probe (`/tmp/freeze-probe/probe.sh`: sway RTT, PSI, dirty pages, D-states,
Steam renderer state, GPU memory → `events.log`) discriminates:

- sway RTT spikes → compositor/driver (§8).
- RTT flat, Steam renderer in `D` → Steam blocked on I/O (§3).
- RTT flat, renderer `R`/`S`, `events.log` empty → CEF-internal (§7).

## Gaps

- No freeze captured.
- Whole-desktop vs Steam-window-only freeze is unknown; it halves the search.
- §8 needs an idle measurement.
- ICPE percentages and the 1 GiB default are second-hand (the local 1000.5 MiB
  corroborates the cap).
