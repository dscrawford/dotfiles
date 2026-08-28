# Watchdog and SysRq: are they robust recovery mechanisms for the BAR1 hang?

*Generated: 2026-08-24 | Sources: 40+ | Confidence: High on the watchdog verdict, Medium on SysRq efficacy*

## Executive summary

**The hardware watchdog is the wrong tool for this failure and will not fire.** It
resets the box only when *PID 1 or the kernel* stops running. In the NVIDIA hang
class you actually have, the kernel stays alive — SSH keeps working, systemd keeps
scheduling — so systemd keeps petting the watchdog forever while your display is
frozen. This corrects Tier 3 of `bar1-crash-research.md`, which guessed the
watchdog "would likely have fired." The evidence says it would not have.

**SysRq is the right tool, and it is currently 90% disabled on this machine.**
`kernel.sysrq = 16` means only `S` (sync) works; `R`, `E`, `I`, `U`, `B` all print
`This sysrq operation is disabled`. Any past impression that "SysRq didn't work"
during a hang is confounded — five of the six keys were never enabled.

**Side effects are real but small and controllable.** The honest risk of SysRq is
physical access: anyone at your keyboard can force an unclean reboot at a locked
screen. Using mask `244` instead of `1` gets you the full REISUB sequence while
excluding the kernel-memory-dump keys that every distro deliberately withholds.

## 1. What these things actually are

### Hardware watchdog

A countdown timer in the chipset, below the OS. Something in userspace must
repeatedly "pet" it before it expires; if the pet stops, the chipset resets the
machine — a hard reset, identical to your front-panel reset button. No sync, no
unmount, no filesystem flush.

`RuntimeWatchdogSec=` (NixOS: `systemd.watchdog.runtimeTime`) tells **PID 1** to be
the petter. systemd opens `/dev/watchdog0`, programs the timeout, and pings from
its main event loop. Current source pings at `timeout/4`, not the `timeout/2` the
manpage claims ([watchdog.c](https://raw.githubusercontent.com/systemd/systemd/main/src/shared/watchdog.c)),
so at 60s you get a ping every ~15s and ~4 missed pings of slack.

The scope is narrow and explicitly stated by systemd's author: it supervises
**the kernel and PID 1 only** ([0pointer.de](http://0pointer.de/blog/projects/watchdog.html)).
Hung *services* are a different mechanism (`WatchdogSec=` per unit). A hung *GPU*
is not covered by either.

### Magic SysRq

A kernel key combination — `Alt+SysRq+<letter>` — handled by an input filter
registered **directly in the input core**, below evdev and below any userspace
grab ([Torokhov, LKML](https://lkml.iu.edu/hypermail/linux/kernel/1003.2/00544.html)).
That placement is the whole point: it works when X/Wayland/the compositor is
wedged, because it never goes through them. The kernel docs describe it as
responding "regardless of whatever else it is doing, unless it is completely
locked up" ([kernel.org](https://www.kernel.org/doc/html/latest/admin-guide/sysrq.html)).

**REISUB** is the graceful-panic sequence, held `Alt+SysRq` throughout:

| Key | Bit | Action |
|---|---|---|
| **R** | 4 | unRaw — take the keyboard back from X |
| **E** | 64 | tErminate — SIGTERM all processes |
| **I** | 64 | kIll — SIGKILL all processes |
| **S** | 16 | Sync — flush all filesystem buffers to disk |
| **U** | 32 | Unmount — remount everything read-only |
| **B** | 128 | reBoot — immediate reset |

`S` and `U` are what make this *better* than the reset button: they flush and
quiesce the filesystems before the reset.

`kernel.sysrq` is a bitmask gating which keys are permitted. Your `16` = sync only.

## 2. Why the watchdog won't fire for you

This is the load-bearing finding, and it is well evidenced.

**Mechanism.** systemd pets the watchdog from PID 1's event loop. If the kernel is
scheduling and PID 1 is not blocked, the pets continue regardless of how broken
anything else is.

**How far that goes.** systemd issue [#7063](https://github.com/systemd/systemd/issues/7063)
documents a machine whose root filesystem was *gone* — journald, udevd, networkd
all failed, the emergency shell itself could not start — and systemd kept petting
the watchdog for 20+ minutes. The reporter's request that "a failed emergency
shell should be probably treated as a good reason to stop poking the watchdog
timer" was declined. It does not.

**Your specific failure class keeps the kernel alive.** From
[open-gpu-kernel-modules#1134](https://github.com/NVIDIA/open-gpu-kernel-modules/issues/1134),
the same BAR1/`__nv_drm_gem_nvkms_map` bug matching your crash:

> "`systemctl reboot` was invoked **from an SSH session** and hung at `nvidia_drm`
> module teardown for >5 minutes… Recovery required holding the hardware power
> button. **The system was otherwise functional throughout: SSH stayed up.**"

And [#1289](https://github.com/NVIDIA/open-gpu-kernel-modules/issues/1289):
"The system itself stays alive (SSH/background services keep running)."

If SSH is answering, PID 1 is running, and the watchdog is being petted.

**No one has ever reported this working.** Searching the NVIDIA open-kernel-modules
tracker across #1289, #1246, #1243, #1187, #1134, #1097, #1045, #1063, #979 for
watchdog usage turned up **zero** cases of anyone recovering a GPU hang with
`/dev/watchdog`. Every hit was either SysRq or NVIDIA's *own* internal "RC
watchdog" (`RC watchdog: GPU is probably locked!`), which is a GPU-side timeout
that in these reports fails to recover — #1134 logs hundreds of
`NV_ERR_RESET_REQUIRED` assertions because "the chip-reset path itself was wedged."

**Residual case where it would fire:** if PID 1 itself blocked in D-state on the
NVIDIA RM lock. Possible in principle. The #1134 evidence that SSH and userspace
stayed responsive argues against it in practice.

## 3. Watchdog side effects, if you enabled it anyway

Good news specific to your board — this is better than the AMD average:

```
sp5100-tco: Using 0xfeb00000 for watchdog MMIO address
sp5100-tco: initialized. heartbeat=60 sec (nowayout=0)
max_timeout: 65535
```

It initialized cleanly. That is *not* typical. `sp5100_tco` is commonly
firmware-disabled on consumer AMD boards — MSI B350M/TOMAHAWK, ASUS ROG Strix
X470-I, MSI MEG X570 ACE all report `Watchdog hardware is disabled`
([LKML test matrix](https://www.mail-archive.com/linux-kernel@vger.kernel.org/msg1582035.html),
[Arch BBS](https://bbs.archlinux.org/viewtopic.php?id=239075)) — and there is a
still-open MMIO regression from commit `1f182aca2300` (5.18-rc1, backported to
5.17.10/5.15.42) that broke SB800 TCO watchdogs from 5.17 through 6.7+, re-reported
to LKML in Feb 2025 and never fixed
([spinics](https://www.spinics.net/lists/kernel/msg5574850.html),
[Debian #1054231](https://lists.debian.org/debian-kernel/2025/02/msg00921.html)).
Your BIOS 5044 leaves it enabled and your kernel probes it. You dodged both.

The real side effects:

- **Silent no-op if the timeout exceeds hardware max.** systemd logs `Failed to set
  timeout to Ns: Invalid argument` **to the journal only** and then runs with *no
  watchdog at all* ([systemd#27427](https://github.com/systemd/systemd/issues/27427)).
  Not a risk for you — max_timeout is 65535s.
- **Backwards clock jumps stop the pings.** If timesyncd pulls the clock backwards
  at boot, systemd stops petting and the box resets seconds later
  ([systemd#5014](https://github.com/systemd/systemd/issues/5014), closed
  `not-our-bug` — still live behavior).
- **NixOS has broken this before.** [nixpkgs#131920](https://github.com/NixOS/nixpkgs/issues/131920):
  commit `b361dcf` on 21.05/unstable broke the keep-alives, and machines with
  `RuntimeWatchdogSec=1m` rebooted 2–8 minutes after *every* boot. A distro-side
  change, not a hardware fault.
- **No pretimeout available on your hardware.** `pretimeout_available_governors`
  reads `n/a`, so `RuntimeWatchdogPreSec=` + `panic` governor is not an option.
  That matters: it is the documented way to get a kernel panic and a trace
  *before* the hard reset. Without it, a spurious watchdog reboot leaves **zero
  diagnostic evidence** — no panic, no log, no kdump. That is the single worst
  property of enabling it here.
- **Suspend/resume is unverified for this driver.** The analogous `iTCO_wdt` bug —
  timeout stops taking effect after suspend, system reboots despite keepalives —
  is documented on [LKML](https://lkml.iu.edu/1204.1/03510.html). I found **no**
  report either way for `sp5100_tco`. systemd does not disarm around suspend.
  Genuine evidence gap.
- **Poettering's own advice:** "functionality like this makes little sense on the
  desktop," and specifically "Don't enable this feature while you hack. Otherwise
  your system might suddenly reboot if you are in the middle of tracing through
  PID 1 with gdb" ([0pointer.de](http://0pointer.de/blog/projects/watchdog.html)).
- **Cost when idle: negligible.** One `ioctl(WDIOC_KEEPALIVE)` per interval from an
  existing event loop, ~4/minute at 60s. No measurable performance impact found.

**Verdict:** low direct risk on your hardware, but it cannot fire for your bug, and
without pretimeout support any false positive it *does* produce is undebuggable.
Not worth it.

## 4. SysRq side effects — the honest list

### The security risk is physical access, and it is real

- **`SysRq-b`/`SysRq-o` at a locked screen** force an unclean reboot/poweroff with
  no authentication. Unambiguous and documented
  ([RH bugzilla 982200](https://bugzilla.redhat.com/show_bug.cgi?id=982200),
  [Arch BBS](https://bbs.archlinux.org/viewtopic.php?id=252586)). This is a local
  DoS primitive against a locked machine.
- **Counterargument that applies to your situation:** someone standing at your
  desktop already has the physical reset button and the power switch. The marginal
  capability SysRq adds is close to zero for a home desktop — this is the explicit
  consensus position in the [Linux Mint thread](https://forums.linuxmint.com/viewtopic.php?t=298367).
  It would be a different answer for a laptop you carry into hostile environments.
- **`SysRq-f` (OOM-kill) may unlock the screen** by killing the locker. Kicksecure
  asserts this ([kicksecure.com](https://www.kicksecure.com/wiki/SysRq)); jwz's
  xscreensaver FAQ confirms OOM-kill-unlocks-screen as a phenomenon but does not
  discuss SysRq as the trigger. Untested on modern Wayland — flagged as inference.
- **`SysRq-k` (SAK)** kills programs on the current VC. Whether that reliably kills
  a Wayland compositor's lock screen under seat management is **not documented
  anywhere I could find** — Kicksecure lists it as an open question too.

### Information disclosure — the underrated one, and the reason not to use `sysrq=1`

Bit `8` enables `t`/`p`/`m`/`l`/`d` — dump all tasks, registers, memory info, CPU
backtraces, held locks — straight to the console, readable by anyone standing
there, regardless of `kptr_restrict` posture. That is the standard KASLR-defeat
primitive. `SysRq-c` deliberately crashes and, with kdump configured, writes RAM
**including user data** to disk on demand from the keyboard.

Every mainstream distro default deliberately excludes bit 8. Ubuntu's rationale is
on record: 176 was chosen "for security reasons, considering a situation when a
malicious user at your keyboard may dump the contents of memory to the console"
([Launchpad #1962038](https://bugs.launchpad.net/bugs/1962038)).

**This is why `244` beats `1`.** `244 = 4+16+32+64+128` is exactly the REISUB set
and nothing else — no dumps, no console loglevel control, no RT renice.

### Distro defaults, for calibration

| Distro | Value | Effect |
|---|---|---|
| Upstream kernel | `1` | everything |
| systemd upstream (→ NixOS, Arch, Fedora effective) | `16` | **sync only** |
| Ubuntu | `176` nominal | S, U, B — no R/E/I |
| Debian | `438` | R, S, U, B — no E/I |
| **`244`** | — | **R, E, I, S, U, B exactly** |

Note Debian and Ubuntu both omit bit 64, so `E` and `I` silently no-op on stock
installs — people follow REISUB tutorials while running a partially dead sequence.

### Other side effects

- **No performance cost.** No benchmark exists, but the runtime cost is one input
  filter callback that early-exits unless the SysRq modifier is latched. No source
  claims a penalty. (Reasoning from architecture, not a measurement.)
- **Accidental triggering is real on some hardware** — Lenovo put PrintScreen
  between right Alt and Ctrl on some ThinkPads, making stray `Alt+SysRq+<letter>`
  easy ([LKML](https://lkml.iu.edu/hypermail/linux/kernel/1301.1/00608.html)). Not
  applicable to a desktop keyboard.
- **"Stuck SysRq" is documented in the kernel's own manual** — a latched modifier
  state can make a later innocuous keystroke read as a SysRq command. Fix is
  tapping shift/alt/ctrl on both sides.
- **Screenshot-tool collision appears to be a myth.** No report found; grim/
  flameshot bind bare PrintScreen, which passes through.
- **Serial console caveat:** any `BREAK` followed within 5s by a letter triggers
  SysRq. Irrelevant unless you add a serial console.
- **`/proc/sysrq-trigger` ignores the bitmask entirely** and is root-only (mode
  0200, verified locally). So `kernel.sysrq=0` buys nothing against a compromised
  root — the sysctl is *purely* a physical-access control.

### Does REISUB still work under systemd?

Not deprecated, but degraded. systemd issue
[#3269](https://github.com/systemd/systemd/issues/3269): after `E`/`I`, PID 1
**restarts the killed services** because it cannot distinguish kernel-forced
termination from ordinary failure — and it does so before `U` lands. Closed
`not-our-bug`. In practice `S`-`U`-`B` is the reliable subset, and it is what the
NVIDIA reporters actually used.

## 5. Does SysRq actually recover *this* hang? Mixed, leaning yes

**Successes on NVIDIA GPU locks:**

| Report | Outcome |
|---|---|
| [#1063](https://github.com/NVIDIA/open-gpu-kernel-modules/issues/1063), RTX 5060 Ti, Xid 8 | "Magic SysRq (REISUB) still works, indicating the kernel remains responsive." Log also shows `This sysrq operation is disabled` — the bitmask problem, live. |
| [#1289](https://github.com/NVIDIA/open-gpu-kernel-modules/issues/1289), RTX 4080/4090, GNOME Wayland | "Magic SysRq remained fully responsive. **REISUB successfully rebooted the machine.**" Reporter also captured `w`/`l` backtraces mid-hang. |
| #1289, RTX 5070 | "Only hardware power-cycle (**or SysRq `s`/`u`/`b`**) recovers." |

**Failures:**

| Report | Outcome |
|---|---|
| #1289, `albanD`, RTX 4090 Laptop | "SysRq W/L/S/U remained functional; **SysRq B did not reboot** this machine during the hang." |
| [#1187](https://github.com/NVIDIA/open-gpu-kernel-modules/issues/1187), Turing BAR1 exhaustion | "no SysRq, requires a power cycle" |
| [#979](https://github.com/NVIDIA/open-gpu-kernel-modules/issues/979), RTX 5080 eGPU | "No kernel panic, no SysRq response." |

Roughly 4 successes to 4 failures, but the failures skew toward *whole-machine*
hard locks (eGPU over Thunderbolt, total wedge), while the successes match the
"kernel alive, GPU wedged, SSH up" signature you actually have.

The `albanD` case is the useful nuance: input delivery survived but `b`
specifically failed. `sysrq-b` calls `emergency_restart()`, which deliberately
skips reboot notifiers, and that has a long history of wedging on some hardware
([LKML](https://lkml.iu.edu/hypermail/linux/kernel/1202.2/01035.html)). If `b`
hangs for you, `reboot=bios|kbd|acpi|efi|pci` is the knob.

**Caveat you should expect:** with `nvidia_drm` wedged, VT switch and console
output go through the same broken stack. Even when SysRq works you get **no
visible feedback** — you are typing blind. Do it slowly and deliberately.

## 6. Filesystem risk — watchdog is not safer than your reset button

A watchdog reset and a front-panel reset are the *same event* to the filesystem:
abrupt CPU reset, no sync, no remount-ro, no flush of the drive's write cache. No
source claims the watchdog is gentler; one embedded vendor warns the opposite —
"persistent hard hardware watchdog resets can lead to filesystem corruption," and
recommends trying a software shutdown first
([embeddedts](https://www.embeddedts.com/assets/preventing-filesystem-corruption-in-embedded-linux)).
On ext4, journal replay handles metadata routinely; in-flight data is lost either
way.

**The asymmetry is entirely on SysRq's side.** `s` (sync) then `u` (remount-ro)
before `b` is strictly better than both the watchdog and the reset button, because
it flushes and quiesces first. That is the actual safety win here, and the #1289
reporters confirm `s` and `u` keep working during these hangs even when `b`
sometimes doesn't.

## Recommendations, revised

1. **`boot.kernel.sysctl."kernel.sysrq" = 244;`** — highest value, near-zero cost,
   currently blocked by systemd's default of 16. Gives exactly REISUB with no
   memory-dump exposure. Then actually test `Alt+SysRq+s`,`u`,`b` during the next
   hang.
2. **Use SSH as the primary recovery path.** `sshd` is already active and enabled
   here, and #1134 proves SSH survives this hang class. From your phone or laptop:
   `echo s | sudo tee /proc/sysrq-trigger`, then `u`, then `b`. This bypasses the
   bitmask entirely and is the cleanest recovery available. Note `systemctl reboot`
   over SSH is **not** equivalent — it demonstrably hangs at `nvidia_drm` teardown.
3. **Shorten `RebootWatchdogSec` from the 10min default to ~1min.** This watchdog
   *is* already armed, in the second shutdown phase only, and it directly targets
   the "`systemctl reboot` hangs forever" symptom. Cheap and real.
4. **Consider `kernel.hung_task_panic=1` + `kernel.panic=10`** — the only credible
   *automatic* recovery. The hung-task detector does fire in these freezes (#1289
   leads with hung-task output for the KMS thread in D-state). Caveats: 120s
   default delay; it only sees `TASK_UNINTERRUPTIBLE`, and the actual lock holder
   in #1289 spins in `R` state, so you're relying on a victim blocking; and false
   positives on slow I/O will panic a desktop. Medium confidence — test before
   committing to it.
5. **Do not enable `RuntimeWatchdogSec`.** It cannot fire for this bug, and your
   hardware has no pretimeout governor, so any false positive it produces is
   undebuggable.
6. **Optional: netconsole or serial console.** Would make SysRq `w`/`l` output
   readable during a freeze, and would let you file a much stronger upstream report
   — the #1289 reporters got NVIDIA's attention precisely by attaching those
   backtraces.

## Key takeaways

1. The watchdog watches PID 1, not your GPU. In your hang PID 1 is fine, so it
   never fires. This corrects Tier 3 of `bar1-crash-research.md`.
2. SysRq was never actually tested here — `kernel.sysrq=16` disabled 5 of the 6
   REISUB keys.
3. Use `244`, not `1`. Same recovery capability, excludes the memory-dump keys.
4. The only genuine SysRq risk on a home desktop is someone at your keyboard
   forcing a reboot — who could already press your reset button.
5. `s`+`u` before `b` is the one option that is *safer* than what you do today.
6. SSH-in-and-`echo b > /proc/sysrq-trigger` is the best recovery path and works
   right now, no config change needed.

## Sources

1. [kernel.org: Magic SysRq](https://www.kernel.org/doc/html/latest/admin-guide/sysrq.html) — bitmask, `/proc/sysrq-trigger` bypass, "unless completely locked up"
2. [systemd sysctl.d/50-default.conf](https://github.com/systemd/systemd/blob/main/sysctl.d/50-default.conf) — upstream `kernel.sysrq = 16`
3. [Poettering, "Watchdogs"](http://0pointer.de/blog/projects/watchdog.html) — PID 1 pets it; scope is PID1+kernel; "little sense on the desktop"
4. [systemd-system.conf(5)](https://manpages.debian.org/testing/systemd/systemd-system.conf.5.en.html) — RuntimeWatchdogSec / RebootWatchdogSec / RuntimeWatchdogPreSec
5. [systemd/systemd#7063](https://github.com/systemd/systemd/issues/7063) — watchdog petted through total system failure
6. [systemd/systemd#27427](https://github.com/systemd/systemd/issues/27427) — silent no-op when timeout exceeds hardware max
7. [systemd/systemd#5014](https://github.com/systemd/systemd/issues/5014) — backwards clock jump stops pings
8. [systemd/systemd#3269](https://github.com/systemd/systemd/issues/3269) — PID 1 restarts services killed by SysRq E/I
9. [NixOS/nixpkgs#131920](https://github.com/NixOS/nixpkgs/issues/131920) — NixOS regression caused 2–8min reboot loops
10. [systemd watchdog.c](https://raw.githubusercontent.com/systemd/systemd/main/src/shared/watchdog.c) — pings at timeout/4
11. [open-gpu-kernel-modules#1134](https://github.com/NVIDIA/open-gpu-kernel-modules/issues/1134) — your bug; SSH stayed up throughout
12. [#1289](https://github.com/NVIDIA/open-gpu-kernel-modules/issues/1289) — REISUB success and the `albanD` `b`-failed case
13. [#1063](https://github.com/NVIDIA/open-gpu-kernel-modules/issues/1063) — REISUB works; shows `sysrq operation is disabled` in the wild
14. [#1187](https://github.com/NVIDIA/open-gpu-kernel-modules/issues/1187) / [#979](https://github.com/NVIDIA/open-gpu-kernel-modules/issues/979) — no-SysRq hard locks
15. [LKML: SysRq as separate input handler](https://lkml.iu.edu/hypermail/linux/kernel/1003.2/00544.html) — why it survives a wedged compositor
16. [LKML: sp5100_tco test matrix](https://www.mail-archive.com/linux-kernel@vger.kernel.org/msg1582035.html) — per-board firmware disabling
17. [spinics: sp5100_tco MMIO regression](https://www.spinics.net/lists/kernel/msg5574850.html) / [Debian #1054231](https://lists.debian.org/debian-kernel/2025/02/msg00921.html) — broken 5.17→6.7+, unfixed
18. [LKML: iTCO_wdt suspend bug](https://lkml.iu.edu/1204.1/03510.html) — watchdog/suspend hazard class
19. [Launchpad #1962038](https://bugs.launchpad.net/bugs/1962038) — Ubuntu's 176 rationale: prevent console memory dumps
20. [RH bugzilla 982200](https://bugzilla.redhat.com/show_bug.cgi?id=982200) — Fedora declines sysrq; "no mechanism for a clean shutdown"
21. [Kicksecure: SysRq](https://www.kicksecure.com/wiki/SysRq) — hardening case for `kernel.sysrq=0`
22. [Linux Mint forum #298367](https://forums.linuxmint.com/viewtopic.php?t=298367) — physical-access counterargument
23. [embeddedts: preventing FS corruption](https://www.embeddedts.com/assets/preventing-filesystem-corruption-in-embedded-linux) — watchdog resets can corrupt; journaling "far from immune"
24. [LKML: sysrq-b / emergency_restart hangs](https://lkml.iu.edu/hypermail/linux/kernel/1202.2/01035.html) — why `b` sometimes fails
25. [docs.kernel.org: lockup watchdogs](https://docs.kernel.org/admin-guide/lockup-watchdogs.html) — why NMI watchdog is inapplicable
26. [Arch BBS #163768](https://bbs.archlinux.org/viewtopic.php?id=163768) — desktop watchdog reports of spurious resets
27. [major.io: emergency reboot](https://major.io/p/linux-emergency-reboot-or-shutdown-with-magic-commands/) — S-U-B ordering rationale

## Methodology

Three parallel research agents across ~40 sources (kernel.org docs, systemd source
and issue tracker, LKML, distro bug trackers, NVIDIA open-kernel-modules issues),
plus direct local verification on this host: watchdog identity/state/limits,
`sp5100_tco` probe log, sysctl values, hung-task config, sshd state.

Sub-questions: (1) watchdog mechanics and documented side effects; (2) `sp5100_tco`
reliability on AMD consumer boards; (3) `kernel.sysrq` bitmask semantics and
security surface; (4) REISUB viability under systemd; (5) whether either mechanism
empirically recovers an NVIDIA Xid hang.

**Gaps, stated honestly:** no report anywhere of a hardware watchdog recovering an
NVIDIA GPU hang (absence of evidence, but a wide search); `sp5100_tco` behavior
across suspend/resume is undocumented; `SysRq-k` lock-screen bypass on modern
Wayland is unverified even by the sources that raise it; no performance measurement
exists for either feature.
