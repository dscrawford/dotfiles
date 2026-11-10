# Watchdog and SysRq as recovery for the BAR1 hang

*2026-08-24. 40+ sources plus local checks. High confidence on the watchdog verdict,
medium on SysRq efficacy.*

## Summary

- **The hardware watchdog won't fire.** It resets only when PID 1 or the kernel stops.
  In this NVIDIA hang the kernel lives (SSH works, systemd schedules), so systemd keeps
  petting it. This corrects step 3 of `bar1-crash-research.md`.
- **SysRq is the right tool and is mostly disabled.** `kernel.sysrq = 16` allows only
  `S`; `R`, `E`, `I`, `U`, `B` print `This sysrq operation is disabled`. Any past "SysRq
  didn't work" is confounded.
- **Side effects are small.** The real risk is someone at the keyboard forcing a reboot
  at a locked screen. Mask `244` gives REISUB without the memory-dump keys.

## 1. Mechanisms

**Hardware watchdog:** a chipset countdown that hard-resets (like the reset button: no
sync, no unmount) unless pinged. `RuntimeWatchdogSec=` (`systemd.watchdog.runtimeTime`)
makes PID 1 ping `/dev/watchdog0` from its event loop, at `timeout/4` in current source
([watchdog.c](https://raw.githubusercontent.com/systemd/systemd/main/src/shared/watchdog.c)).
Scope is **kernel and PID 1 only** ([Poettering](http://0pointer.de/blog/projects/watchdog.html));
a hung GPU isn't covered.

**Magic SysRq:** an input filter in the input core, below evdev and any userspace grab
([LKML](https://lkml.iu.edu/hypermail/linux/kernel/1003.2/00544.html)), so it works with
the compositor wedged, "unless [the kernel] is completely locked up"
([kernel.org](https://www.kernel.org/doc/html/latest/admin-guide/sysrq.html)).

| Key | Bit | Action |
|---|---|---|
| **R** | 4 | unRaw: take the keyboard back |
| **E** | 64 | SIGTERM all |
| **I** | 64 | SIGKILL all |
| **S** | 16 | sync filesystems |
| **U** | 32 | remount read-only |
| **B** | 128 | immediate reboot |

`S` and `U` make it better than the reset button.

## 2. Why the watchdog won't fire

- [systemd#7063](https://github.com/systemd/systemd/issues/7063): root fs gone,
  journald/udevd/networkd and even the emergency shell failed, and systemd kept petting
  for 20+ minutes; the request to stop was declined.
- [#1134](https://github.com/NVIDIA/open-gpu-kernel-modules/issues/1134) (this bug):
  "`systemctl reboot` was invoked from an SSH session and hung at `nvidia_drm` module
  teardown for >5 minutes … **SSH stayed up.**"
  [#1289](https://github.com/NVIDIA/open-gpu-kernel-modules/issues/1289): "SSH/background
  services keep running."
- Across #1289, #1246, #1243, #1187, #1134, #1097, #1045, #1063, #979: **zero** watchdog
  recoveries. Hits were SysRq or NVIDIA's internal RC watchdog, which fails here (#1134:
  hundreds of `NV_ERR_RESET_REQUIRED`).
- It would fire only if PID 1 blocked in D-state on the RM lock; #1134 argues against it.

## 3. Watchdog side effects

This board's `sp5100_tco` initializes cleanly (`heartbeat=60 sec (nowayout=0)`,
`max_timeout: 65535`), unlike many consumer AMD boards
([LKML matrix](https://www.mail-archive.com/linux-kernel@vger.kernel.org/msg1582035.html))
and despite an unfixed MMIO regression from `1f182aca2300` (5.17–6.7+,
[Debian #1054231](https://lists.debian.org/debian-kernel/2025/02/msg00921.html)).

- Timeout above hardware max: journal-only error, then no watchdog
  ([systemd#27427](https://github.com/systemd/systemd/issues/27427)). Not an issue here.
- A backwards clock jump at boot stops pings and resets the box
  ([systemd#5014](https://github.com/systemd/systemd/issues/5014)).
- NixOS broke keep-alives once; `RuntimeWatchdogSec=1m` rebooted 2–8 min after every
  boot ([nixpkgs#131920](https://github.com/NixOS/nixpkgs/issues/131920)).
- **No pretimeout**: `pretimeout_available_governors` is `n/a`, so a false-positive
  reset leaves no panic, log or kdump. The worst property here.
- Suspend/resume unverified for `sp5100_tco` (`iTCO_wdt` has such a bug,
  [LKML](https://lkml.iu.edu/1204.1/03510.html)).
- Poettering: "makes little sense on the desktop". Idle cost negligible.

**Verdict:** can't fire for this bug; any false positive is undebuggable. Skip it.

## 4. SysRq side effects

- **Physical access:** `SysRq-b`/`-o` reboot or power off a locked machine
  ([RH 982200](https://bugzilla.redhat.com/show_bug.cgi?id=982200)). At a home desktop
  that person already has the reset button
  ([Mint](https://forums.linuxmint.com/viewtopic.php?t=298367)).
- `SysRq-f` may unlock the screen by OOM-killing the locker
  ([Kicksecure](https://www.kicksecure.com/wiki/SysRq)); `SysRq-k` vs a Wayland lock is
  undocumented. Both untested.
- **Information disclosure, the reason not to use `1`:** bit 8 enables
  `t`/`p`/`m`/`l`/`d` dumps of tasks, registers and memory to the console (a KASLR
  defeat), and `SysRq-c` with kdump writes RAM to disk. Ubuntu excludes it for that
  reason ([Launchpad #1962038](https://bugs.launchpad.net/bugs/1962038)).
  `244 = 4+16+32+64+128` is exactly REISUB.

| Distro | Value | Effect |
|---|---|---|
| Upstream kernel | `1` | everything |
| systemd (→ NixOS, Arch, Fedora) | `16` | **sync only** |
| Ubuntu | `176` | S, U, B |
| Debian | `438` | R, S, U, B |
| **`244`** | — | **R, E, I, S, U, B** |

- No measurable cost (one early-exit input callback; reasoning, not measured).
- A latched modifier can turn a later keystroke into a SysRq command; tap
  shift/alt/ctrl on both sides.
- `/proc/sysrq-trigger` ignores the mask and is root-only (mode 0200, verified), so the
  sysctl only controls physical access.
- Under systemd, PID 1 restarts services killed by `E`/`I` before `U` lands
  ([systemd#3269](https://github.com/systemd/systemd/issues/3269)); `S`-`U`-`B` is the
  reliable subset.

## 5. Does SysRq recover this hang?

| Report | Outcome |
|---|---|
| [#1063](https://github.com/NVIDIA/open-gpu-kernel-modules/issues/1063), RTX 5060 Ti | REISUB works (log also shows `sysrq operation is disabled`) |
| #1289, RTX 4080/4090, GNOME Wayland | "REISUB successfully rebooted the machine" |
| #1289, RTX 5070 | power-cycle "or SysRq `s`/`u`/`b`" |
| #1289, RTX 4090 Laptop | W/L/S/U worked; **B did not reboot** |
| [#1187](https://github.com/NVIDIA/open-gpu-kernel-modules/issues/1187), Turing BAR1 | no SysRq |
| [#979](https://github.com/NVIDIA/open-gpu-kernel-modules/issues/979), 5080 eGPU | no SysRq |

Failures skew to whole-machine locks; successes match this "GPU wedged, SSH up" case.
`sysrq-b` calls `emergency_restart()`, which can wedge on some hardware
([LKML](https://lkml.iu.edu/hypermail/linux/kernel/1202.2/01035.html)); try
`reboot=bios|kbd|acpi|efi|pci` if so. Expect no visible feedback: type slowly.

A watchdog reset is the same as the reset button to the filesystem
([embeddedts](https://www.embeddedts.com/assets/preventing-filesystem-corruption-in-embedded-linux));
only `s` + `u` before `b` is safer.

## Recommendations

1. `boot.kernel.sysctl."kernel.sysrq" = 244;` then test `Alt+SysRq+s`,`u`,`b` on the next hang.
2. SSH is the primary path: `echo s | sudo tee /proc/sysrq-trigger`, then `u`, then `b`.
   Not `systemctl reboot`, which hangs in `nvidia_drm` teardown.
3. `RebootWatchdogSec` 10 min → ~1 min; it's armed only in the final shutdown phase and
   targets the hung-reboot symptom.
4. Maybe `kernel.hung_task_panic=1` + `kernel.panic=10`, the only credible automatic
   recovery (#1289 shows hung-task output for the KMS thread). Caveats: 120 s delay; sees
   only D-state victims (the lock holder spins in `R`); false positives on slow I/O. Test
   first.
5. **Don't enable `RuntimeWatchdogSec`.**
6. Optional netconsole/serial console, to read SysRq `w`/`l` output and file a stronger
   upstream report.

Gaps: no report of a watchdog recovering an NVIDIA hang (wide search); `sp5100_tco`
across suspend is undocumented; `SysRq-k` vs Wayland lock unverified.
