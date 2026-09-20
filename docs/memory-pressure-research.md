# Reserving memory for stability: why a runaway app freezes this desktop

*Generated: 2026-09-18 | Sources: ~45 (systemd v261 source, kernel docs, man pages, distro policy) plus live measurement on this machine | Confidence: High on the mechanism and the diagnosis (read from systemd's source at the exact version installed, plus `oomctl` and cgroupfs on the running box); Medium on the numeric tuning (no reproduction of the freeze has been run yet)*

## Executive summary

**Yes, memory can be reserved — but the knob you want is a cgroup limit on the
apps, not a kernel reserve, and the reason this machine still freezes is not a
missing knob. It is that every graphical process lives in one cgroup.**

`hosts/local/priority.nix` already does zram, four reclaim sysctls, systemd-oomd
on all three slices, `MemoryLow` for the audio path, and
`ManagedOOMPreference=avoid` on PipeWire. Five things are wrong with it, all
verified live:

1. **oomd's most likely victim is the entire desktop.** sway, waybar, mako,
   swaybg, Xwayland, Emacs and all of Firefox — 55 processes, 7.2 G of the
   8.3 G in use — sit in a single leaf cgroup, `session-3.scope`. oomd selects a
   leaf and `SIGKILL`s it recursively. Killing "the app that hogged memory"
   means killing the session.
2. **The `MemoryLow` chain is broken one level up from where it matters.**
   `user-1000.slice` has `memory.low = 0`, so PipeWire's 128 M protection is
   nullified.
3. **`DefaultMemoryPressureLimit = "60%"` is dead code.** Every monitored cgroup
   runs at 80%.
4. **Nothing watches swap.** `oomctl` lists zero swap-monitored cgroups despite
   35 G of swap.
5. **oomd fires on PSI `full`, not `some`** — a threshold far more extreme than
   the number suggests, and gated behind a 30 s reclaim-activity check.

The fix is three layers, in this order: put apps in their own cgroups, cap those
cgroups, and repair the protection chain. Kernel `vm.*` reserves are the wrong
tool for this and are covered in §6 mainly to rule them out.

## 1. What the live system shows

Measured on this box, 2026-09-18, systemd 261.1, kernel 6.18.44, 62 Gi RAM,
31.4 G zram (prio 5) + 4 G disk swap (prio -2):

| Fact | Value |
|---|---|
| `session-3.scope` memory / process count | **7.2 G / 55 procs** |
| Its subgroups | **none — it is a leaf** |
| Its `memory.oom.group` | 0 |
| Its `user.oomd_avoid` / `_omit` xattr | **absent** |
| `user-1000.slice` `memory.low` | **0** ← chain break |
| oomd monitored cgroups | `/`, `/system.slice`, `/user.slice`, `app.slice`, `background.slice` |
| Their pressure limit / duration | **80% / 30 s** (not the configured 60%) |
| oomd swap-monitored cgroups | **none** |
| `session.slice` monitored? | **no** (see §5, drop-in collision) |
| `kernel.sysrq` | 16 — REISUB unavailable |

`systemd-cgls` output, trimmed:

```
user-1000.slice
├─user@1000.service
│ ├─session.slice   dbus-broker, pipewire, wireplumber, pipewire-pulse, portals
│ ├─app.slice       ollama, ssh-agent, wivrn, xdg-desktop-portal-{gtk,wlr}, obex
│ └─init.scope
└─session-3.scope   greetd, sway, waybar, mako, swaybg, Xwayland, emacs,
                    firefox ×8, easyeffects, … 55 processes
```

`app.slice` exists and is monitored, but contains only systemd user *services*.
No GUI application is in it. A `MemoryHigh` on `app.slice` today would not
constrain Firefox by a single byte.

## 2. Why one cgroup for the whole session is the bug

systemd's own documentation names this exact failure. From
`systemd-oomd.service(8)` as installed here:

> Be aware that if you intend to enable monitoring and actions on `user.slice`,
> `user-$UID.slice`, or their ancestor cgroups, it is highly recommended that
> your programs be managed by the systemd user manager to prevent running too
> many processes under the same session scope (and thus **avoid a situation
> where memory intensive tasks trigger systemd-oomd to kill everything under the
> cgroup**). If you're using a desktop environment like GNOME or KDE, it already
> spawns many session components with the systemd user manager.

`priority.nix:49` sets `enableUserSlices = true`, which is precisely "monitoring
and actions on `user.slice`". GNOME and KDE escape this because their session
managers launch components as systemd user units; sway `exec`s its children, so
they inherit the logind session scope. Every `exec` and `bindsym … exec` line in
`shared/sway/config.nix` — `mako`, `easyeffects`, `foot`, `wmenu-run`, `firefox`
— lands in `session-3.scope`.

### Candidate selection, read from systemd v261

Verified by fetching `src/oom/` at tag `v261`, the version installed here.

`recursively_get_cgroup_context()` in `oomd-manager.c:291` descends to **leaf**
cgroups, stopping early at any cgroup with `memory.oom.group=1`:

```c
else if (r == 0) { /* No subgroups? We're a leaf node */
        r = oomd_insert_cgroup_context(NULL, new_h, path);
```

Ranking is by reclaim rate, not size — `oomd_select_by_pgscan_rate()` sorts with
`compare_pgscan_rate_and_memory_usage` (`oomd-util.c:586`). The kill is
recursive:

```c
r = oomd_cgroup_kill(ks->manager, ks->ctx, /* recurse= */ true, ks->reason);
```

`session-3.scope` is a leaf, carries no `oomd_omit`/`oomd_avoid` xattr, holds the
most memory in the tree, and under a Firefox blowup would have the highest
pgscan rate. It is the number-one candidate, and all 55 processes go with it.

The same class of report exists upstream: [omarchy#9799](https://github.com/omacom/omarchy/issues/9799),
where everything launched from one terminal shared a scope and 2,104 processes
were killed at once.

## 3. oomd fires far later than "80%" sounds — and can decline to fire at all

Three facts, none of them in any man page, all read from v261 source.

**It compares PSI `full`, not `some`.** `oomd-util.c:684`:

```c
r = read_resource_pressure(p, PRESSURE_TYPE_FULL, &ctx->memory_pressure);
```

Per the [kernel PSI docs](https://docs.kernel.org/accounting/psi.html), `some`
means at least one task is stalled; `full` means *every* non-idle task is
stalled simultaneously — "a workload that spends extended time in this state is
considered to be thrashing". So the effective trigger on this machine is
**`full` avg10 > 80% sustained 30 s**: near-total stall, for half a minute.
That is long past the point a human calls it a freeze.

**There is a mandatory reclaim gate.** `oomd-manager.c:591`:

```c
/* Check if there was reclaim activity in the given interval. ... Thus if there
 * isn't any reclaim pressure, no need to kill something (it won't help anyways). */
if ((now(CLOCK_MONOTONIC) - t->last_had_mem_reclaim) > RECLAIM_DURATION_USEC)
        continue;
```

`last_had_mem_reclaim` only refreshes while `pgscan` is climbing. Pressure alone
never triggers a kill; pressure *plus* active page scanning does. This is the
real reason the man page insists on swap, and why an all-anonymous working set
with nothing to reclaim can livelock past oomd entirely.

**Constants** (`oomd-manager.h`, v261, confirmed against `oomctl` output):

| Constant | Value |
|---|---|
| `MEM_PRESSURE_INTERVAL_USEC` | 1 s poll |
| `SWAP_INTERVAL_USEC` | 0.15 s |
| `DEFAULT_MEM_PRESSURE_DURATION_USEC` | 30 s |
| `DEFAULT_MEM_PRESSURE_LIMIT_PERCENT` | 60 |
| `DEFAULT_SWAP_USED_LIMIT_PERCENT` | 90 |
| `RECLAIM_DURATION_USEC` | 30 s |
| `POST_ACTION_DELAY_USEC` | 15 s |

**Swap action needs both conditions** (`oomd-manager.c:478`):

```c
if (oomd_mem_available_below(&m->system_context, 10000 - m->swap_used_limit_permyriad) &&
                oomd_swap_free_below(&m->system_context, 10000 - m->swap_used_limit_permyriad)) {
```

At `SwapUsedLimit=90%` that is MemAvailable < 10% **and** swap free < 10%. Moot
here: nothing sets `ManagedOOMSwap=kill`, so the swap path is unreachable
regardless (§4).

This lateness is a known upstream complaint —
[systemd#33486](https://github.com/systemd/systemd/issues/33486) (open since
2024-06), [systemd#25596](https://github.com/systemd/systemd/issues/25596),
[Launchpad #1980169](https://bugs.launchpad.net/bugs/1980169), and
[RHBZ 2248071](https://bugzilla.redhat.com/show_bug.cgi?id=2248071), where
systemd-oomd's own author notes "pressure is not meeting the thresholds we have
set by default for Fedora."

## 4. The three configuration bugs in `priority.nix`

### 4.1 `DefaultMemoryPressureLimit = "60%"` never binds

`oomctl` reports `Default Memory Pressure Limit: 60.00%`, then lists every
monitored cgroup at **80.00%**. NixOS's `enableRootSlice`/`enableSystemSlice`/
`enableUserSlices` each emit an explicit per-slice
`ManagedOOMMemoryPressureLimit = mkDefault "80%"`
([oomd.nix](https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/system/boot/systemd/oomd.nix)),
and a per-unit limit beats the daemon default — `ManagedOOMMemoryPressureLimit=`
"Defaults to 0%", meaning *fall back to oomd.conf*, and it is not 0 here. To
actually lower the threshold, override the per-slice value, not the default.

### 4.2 The `MemoryLow` chain breaks at `user-1000.slice`

`systemd.resource-control(5)`:

> For a protection to be effective, it is generally required to set a
> corresponding allocation on all ancestors, which is then distributed between
> children (with the exception of the root slice).

Measured chain:

```
/user.slice                                      low=512M
/user.slice/user-1000.slice                       low=0      ← break
/user.slice/…/user@1000.service                   low=512M
/user.slice/…/session.slice                       low=512M
/user.slice/…/session.slice/pipewire.service      low=128M
```

`priority.nix` sets `systemd.slices.user` (→ `user.slice`) and
`systemd.services."user@"` (→ `user@.service`) but never `user-1000.slice`, which
sits between them. PipeWire's protection is therefore not effective. NixOS needs
the dash-truncated drop-in for the per-UID slice, because `user-.slice` is not a
real unit:

```nix
systemd.slices."user-" = {
  overrideStrategy = "asDropin";     # → /etc/systemd/system/user-.slice.d/overrides.conf
  sliceConfig.MemoryLow = "2G";
};
```

Documented in `systemd.unit(5)`: "for a unit name `foo-bar-baz.service` not only
the regular drop-in directory `foo-bar-baz.service.d/` is searched but also both
`foo-bar-.service.d/` and `foo-.service.d/`."

### 4.3 No swap-based protection exists

`oomctl` → `Swap Monitored CGroups:` is empty. The NixOS oomd module never emits
`ManagedOOMSwap=`, so with 35 G of swap there is no trigger for a slow
swap-thrash spiral — only the pressure path, with the 30 s reclaim gate.

Note `systemctl show user.slice` printing `ManagedOOMSwap=auto` means *not
monitored*; `auto` is the off position, `kill` is the on position.

Do **not** simply switch it on: both Fedora and Ubuntu retreated from
`ManagedOOMSwap=kill` on `-.slice` because it killed Firefox during heavy but
harmless swap use ([Phoronix](https://www.phoronix.com/news/Ubuntu-Drops-Swap-Kill),
[LP#1972159](https://bugs.launchpad.net/ubuntu/+source/systemd/+bug/1972159)).
Bounding the thrash window with `MemorySwapMax=` on the app slice is the better
trade.

## 5. A drop-in filename collision is silently shielding the audio slice

`systemd.unit(5)`, on unit-type-wide drop-ins:

> Files in `type.d/` have lower precedence compared to files in name-specific
> override directories. The usual rules apply: multiple drop-in files with
> different names are applied in lexicographic order, regardless of which of the
> directories they reside in, so a file in `type.d/` applies to a unit **only if
> there are no drop-ins or masks with that name in directories with higher
> precedence**.

NixOS names every generated drop-in `overrides.conf`. `enableUserSlices` writes
a type-wide `/etc/systemd/user/slice.d/overrides.conf`; `priority.nix:56`
(`systemd.user.slices.session`) writes `session.slice.d/overrides.conf`. Same
filename, higher precedence — so the oomd drop-in is **discarded, not merged**.
Verified:

```
session.slice  DropInPaths=…/session.slice.d/overrides.conf   ManagedOOMMemoryPressure=auto
app.slice      DropInPaths=…/slice.d/overrides.conf           ManagedOOMMemoryPressure=kill
```

and `session.slice` is correspondingly absent from `oomctl`'s monitored list
while `app.slice` and `background.slice` are present.

The outcome is desirable — you do not want oomd killing the audio slice — but it
is an accident. **The general hazard: any `systemd.user.slices.<X>` override you
add silently disables oomd monitoring for `<X>`.** If you cap `app.slice` via
this mechanism, you must restate `ManagedOOM*` in the same drop-in or you will
turn off monitoring for the slice you were trying to protect.

(`ManagedOOMPreference=avoid` on PipeWire *is* working — `user.oomd_avoid="1"` is
set on both the `pipewire.service` and `wireplumber.service` cgroups, so this
filesystem supports the xattrs the feature needs.)

## 6. Kernel reserves: mostly the wrong tool

From [`Documentation/admin-guide/sysctl/vm.rst`](https://docs.kernel.org/admin-guide/sysctl/vm.html):

| sysctl | What it reserves | Verdict here |
|---|---|---|
| `vm.admin_reserve_kbytes` | commit-accounting reserve for `CAP_SYS_ADMIN`; default `min(3% free, 8MB)` — 8192 here | Buys you an ssh/kill during exhaustion. Does nothing for GUI responsiveness. Worth raising to ~256 M as cheap insurance. |
| `vm.user_reserve_kbytes` | 131072 here | **Inert** — "no effect under overcommit modes 0 or 1", and this box is mode 0. |
| `vm.min_free_kbytes` | per-zone `WMARK_MIN`; 67584 here | Marginal. Too high "trigger[s] immediate OOM conditions". |
| `vm.watermark_scale_factor` | when kswapd wakes/sleeps, in 1/10000; default 10 | **The one useful knob**, and already at 125 here. Moves reclaim into kswapd instead of synchronous direct reclaim in the foreground app. |
| `vm.overcommit_memory=2` + ratio | hard cap on committed address space | A real hard stop, but breaks Electron/JVM/Go/Chromium, which reserve huge address space they never touch. **Not for a desktop.** |

None of these bound an app's *resident* memory. Only cgroup `memory.max` does.

## 7. The knobs that actually bound an app

`systemd.resource-control(5)` and [cgroup-v2 docs](https://docs.kernel.org/admin-guide/cgroup-v2.html):

| systemd | cgroup file | Semantics |
|---|---|---|
| `MemoryMin=` | `memory.min` | Hard protection — "won't be reclaimed under any conditions". **Unmeetable → OOM killer.** |
| `MemoryLow=` | `memory.low` | Best-effort protection; may still be reclaimed to avoid an OOM kill. |
| `MemoryHigh=` | `memory.high` | Throttle + heavy reclaim. **Never invokes the OOM killer**; can be exceeded transiently. |
| `MemoryMax=` | `memory.max` | Hard limit; OOM killer runs **inside the cgroup**. |
| `MemorySwapMax=` | `memory.swap.max` | Caps the cgroup's swap — bounds the thrash window. |

systemd's guidance: "use `MemoryHigh=` as the main control mechanism and use
`MemoryMax=` as the last line of defense."

Two properties make `MemoryMax` the right answer to the original question. It
reserves the remainder by construction: if apps may use at most 50 G of 62 G,
12 G is unavailable to them no matter what. And when it trips, the kernel OOM
killer runs *within* that cgroup and picks by `oom_badness` (RSS-weighted) — so
the 20 G Firefox content process dies and sway never notices. That is a strictly
better outcome than oomd's recursive kill of the session scope.

Two caveats:

- **`MemoryHigh` alone can thrash forever.** If the working set genuinely exceeds
  it and swap is available, the cgroup pins at the boundary and swaps
  indefinitely — slow forever instead of dead. Facebook's
  [fbtax2 case study](https://facebookmicrosites.github.io/cgroup2/docs/memory-controller.html)
  hit exactly this and concluded: use `memory.low` for protection, avoid
  aggressive `memory.high` on critical services. Pair `MemoryHigh` with
  `MemoryMax` and `MemorySwapMax`.
- **Charging does not migrate.** "A memory area is charged to the cgroup that
  originally instantiated it and remains charged there until released.
  Migrating a process between cgroups does not transfer already-allocated
  memory." Limiting a scope after the app has allocated is largely futile — the
  limit must exist when the app starts.

`MemoryMin` vs `MemoryLow` for the audio path: prefer `MemoryLow` on the slices,
and reserve a small `MemoryMin` (~128 M) for `pipewire.service` itself. An
unmeetable `memory.min` invokes the OOM killer, which would turn "protect
PipeWire" into "kill the session" — but 128 M out of 62 G is trivially meetable.

## 8. Fixing process placement

Both tools are already in this repo's pinned nixpkgs: **uwsm 0.26.6** and
**app2unit 1.4.4** ([upstream](https://github.com/Vladimir-csp/uwsm),
[app2unit](https://github.com/Vladimir-csp/app2unit)).

**Option A — `app2unit`, incremental, low risk.** Wrap the launchers. `foot`,
`firefox` and `wmenu-run` become `app-*.scope` units under `app.slice`; anything
spawned from a terminal inherits that terminal's scope rather than the session
scope. greetd and sway start exactly as they do now. This is enough to make §7's
limits and oomd's per-app kills meaningful, and it can be done one bindsym at a
time.

Ad-hoc equivalent, **verified working on this machine** (exit 0, then reverted):

```bash
systemd-run --user --scope --slice=app.slice -p MemoryHigh=8G -p MemoryMax=12G firefox
```

**Option B — `programs.uwsm.enable`, structural.** uwsm creates nested
`app-graphical.slice` / `background-graphical.slice` / `session-graphical.slice`
and gives you `uwsm app -s a|b|s -t scope|service -- app`. It also reaches
`graphical-session.target` properly, which would fix the separate problem
recorded in this repo's memory note (tray/GUI autostart must currently use sway
`exec` because that target is never reached under the raw greetd start). Costs:
it forces `services.dbus.implementation = "broker"` and wants to own session
startup, so the greetd command changes. Not yet tested here end to end.

Recommendation: A first, since it is reversible and independent; B when you next
want to revisit the `graphical-session.target` problem, because it solves both.

## 9. Second-layer killers: oomd, earlyoom, nohang

| | Trigger | Granularity | Fires when |
|---|---|---|---|
| **systemd-oomd** | PSI `full` avg10 over N s, **and** active reclaim | whole cgroup, recursive | very late; can decline entirely (§3) |
| **earlyoom** | free RAM % **AND** free swap %, polled ~10×/s | single process | early; blind to refault thrashing |
| **nohang** | mem **OR** swap **OR** zram **OR** PSI, soft+hard levels | single process, regex badness | configurable; cannot be disarmed by idle swap |

**earlyoom's AND is a footgun on this machine.** Upstream MANPAGE: SIGTERM when
*both* available memory and free swap are below their thresholds. With 35 G of
mostly-idle swap the swap condition never trips and earlyoom will watch RAM go
to zero doing nothing. Upstream's own fix: "You can use `-s 100` to have
earlyoom effectively ignore swap usage." So any earlyoom config here needs
`-s 100,100`. Percentage thresholds also scale badly: 10% of 62 G is 6.2 G of
wasted headroom, so prefer absolute KiB via `-M`/`-S`.

Also relevant: earlyoom matches `--avoid`/`--prefer` regexes against `comm`,
which the kernel truncates to 15 characters.

**nohang** is packaged *and* has a NixOS module (`services.nohang.enable`,
`configPath` defaulting to `"desktop"`), landed post-25.11 and present in this
repo's pin. Its unit is self-limited (`Slice=hostcritical.slice`,
`MemoryMax=100M`, `TasksMax=25`). The desktop preset ORs independent triggers —
`psi_checking_enabled = True`, `psi_metrics = full_avg10`,
`soft_threshold_max_psi = 40`, `hard_threshold_max_psi = 90`,
`soft_threshold_min_mem = 5 %`, `hard_threshold_min_mem = 2 %`,
`soft_threshold_max_zram = 55 %` — and ships `@BADNESS_ADJ_RE_REALPATH` lines
protecting desktop components. It sends SIGTERM before SIGKILL and can run an
arbitrary command as the soft action. Actively maintained (pushed 2026-08-05).

Note: a built-in SIGSTOP/throttle mode is **not** documented upstream; you get it
only by configuring `kill -STOP $PID` as a soft action.

**Do not run two killers with overlapping thresholds** — each picks a victim from
its own stale snapshot and you lose two apps where one would do. Fedora's own
migration path was "disable earlyoom, enable systemd-oomd". If you want two
layers, make them deliberately non-overlapping.

Worth knowing: `OOMScoreAdjust=-900` protects against earlyoom's *default*
selection (it reads `/proc/*/oom_score`) but **not** against `--sort-by-rss`, and
not against systemd-oomd at all, which selects cgroups and never consults
`oom_score`.

## 10. zram sizing is on the aggressive side

`zramSwap.memoryPercent = 50` gives 31.4 G of zram on 62 G of RAM. Fedora ships
`min(RAM/2, 4096 MiB)` — capped at 4 G — and
[explains the cap](https://fedoraproject.org/wiki/Changes/SwapOnZRAM): the zram
driver "starts to allocate memory at roughly 1/2 the rate of page outs, due to
compression", and a larger device produces "swap thrashing similar to
conventional swap-on-drive, except it's CPU and memory bound, rather than IO
bound", concluding it is "better to just oom, instead of getting overly
aggressive with the zram device size."

zram is backed by RAM, so filling it consumes the RAM you are trying to free. At
a typical 2–3:1 zstd ratio, a full 31.4 G device occupies ~10–15 G of RAM. With
`vm.swappiness = 150` pushing anon pages out eagerly, that is a lot of rope.

Two further wrinkles:

- **MGLRU is enabled here** (`/sys/kernel/mm/lru_gen/enabled` = `0x0007`), and
  [LWN's 2026-03 review](https://lwn.net/Articles/1060967/) documents an
  anon-vs-file reclaim imbalance under which "swappiness tuning becomes
  ineffective" — directly relevant to a `swappiness = 150` + large-zram setup.
  Its measured wins are server/ChromeOS-shaped; `min_ttl_ms = 1000` is the one
  knob aimed at desktop jank, and it is off by default.
- `vm.watermark_boost_factor = 0` and `vm.watermark_scale_factor = 125` trace to
  [Pop!_OS PR #163](https://github.com/pop-os/default-settings/pull/163), whose
  own justification is "recommended by a Linux-gaming discussion". The direction
  is sound; the exact numbers are folklore, not measurement.

## 11. Recommended changes, in priority order

Not applied — this is a research note. Tier 1 alone removes the
kill-the-whole-desktop failure mode.

**Tier 1 — stop oomd from being able to kill the session.** Either fix placement
(§8) or, as a stopgap, exclude the session scope from candidacy. The repair for
the broken protection chain belongs here too, because it is one line:

```nix
systemd.slices."user-" = {
  overrideStrategy = "asDropin";    # user-.slice is not a real unit
  sliceConfig.MemoryLow = "2G";     # closes the §4.2 chain break
};
```

**Tier 2 — reserve the memory.** Once apps are in `app.slice`, this is the
literal answer to the question. **Restate `ManagedOOM*` in the same drop-in** or
the §5 filename collision silently unmonitors the slice:

```nix
systemd.user.slices.app.sliceConfig = {
  MemoryHigh = "44G";      # ~70% — throttle and reclaim first
  MemoryMax  = "50G";      # ~80% — hard stop, cgroup-internal OOM kill
  MemorySwapMax = "8G";    # bound the thrash window
  # Restated because this drop-in masks oomd's slice.d/overrides.conf:
  ManagedOOMMemoryPressure = "kill";
  ManagedOOMMemoryPressureLimit = "50%";
  ManagedOOMMemoryPressureDurationSec = "10s";
};
```

**Tier 3 — make the audio protection real.** `MemoryMin = "128M"` on
`pipewire.service` (small enough to always be meetable) on top of the repaired
`MemoryLow` chain. `ManagedOOMPreference = "avoid"` is already working.

**Tier 4 — a per-process second layer, if Tier 1 is deferred.** oomd cannot
express "kill Firefox, spare sway" when both are in one cgroup; a per-process
killer can. Either `services.nohang` (`configPath = "desktop"`), or earlyoom with
swap disarmed:

```nix
services.earlyoom = {
  enable = true;
  extraArgs = [
    "-M" "3145728" "-S" "1572864"     # absolute KiB, not percentages
    "-s" "100,100"                     # or the idle 35G of swap disarms it
    "--avoid" "^(sway|Xwayland|waybar|mako|pipewire|wireplumber|systemd|dbus-broker)$"
    "--prefer" "^(firefox|\\.firefox-wrapped|chromium|electron|node|ollama)$"
    "-p"
  ];
};
```

If you adopt this, relax the oomd pressure action on `user.slice` to `"auto"` so
the two do not fight — the approach taken by
[AdrienLemaire/nixdots](https://github.com/AdrienLemaire/nixdots/blob/main/modules/system/memory.nix),
which reached the same diagnosis independently.

**Tier 5 — housekeeping.**
- Drop `settings.OOM.DefaultMemoryPressureLimit` or move the value onto the
  per-slice `ManagedOOMMemoryPressureLimit`; today it does nothing (§4.1).
- Consider `zramSwap.memoryPercent = 25` (§10).
- `vm.admin_reserve_kbytes = 262144` — cheap insurance for a recovery shell.
- `boot.kernel.sysctl."kernel.sysrq" = 244` — `docs/watchdog-sysrq-research.md`
  recommended this and it was never applied; `kernel.sysrq` is still 16, so
  REISUB is unavailable during a freeze.

**Verification.** Reproduce before and after with Fedora's smoke test, which
should kill only the scope:

```bash
systemd-run --user --scope --slice=app.slice -p MemoryMax=4G \
  stress-ng --brk 2 --stack 2 --bigheap 2 --timeout 90s
oomctl                       # confirm limits and monitored cgroups
journalctl -u systemd-oomd   # look for "and there was reclaim activity"
```

## Gaps

- **No freeze has been reproduced.** The 2026-08-30 OOM referenced in
  `priority.nix:31` predates the journal's retention (oldest boot: 2026-09-07),
  and there are no kernel OOM kills or oomd kill events in any retained boot. The
  diagnosis rests on mechanism plus live cgroup state, not on a captured
  incident.
- **uwsm + greetd + sway is untested here.** nixpkgs' example lists sway, but the
  module's documentation is display-manager-oriented.
- **Numeric thresholds are reasoned, not measured** — the 44 G/50 G split and the
  50%/10 s oomd values are starting points.
- Fedora's currently shipped oomd drop-in values were read from CentOS Stream 10
  and two mirrors; `src.fedoraproject.org` blocks automated fetches. Fedora's own
  `Changes/EnableSystemdOomd` wiki page and its QA test case still describe the
  Fedora 34 config (`-.slice` swap kill, `user@.service` at 50%) that is no
  longer shipped.
- No upstream tracker item ties PipeWire xruns specifically to system memory
  pressure. The documented chain is indirect: unmet `RLIMIT_MEMLOCK` → page fault
  in the data loop → fault latency exceeds the buffer period → xrun.

## Sources

**Primary — systemd v261 source** (the version installed here)
1. [`src/oom/oomd-util.c`](https://raw.githubusercontent.com/systemd/systemd/v261/src/oom/oomd-util.c) — `PRESSURE_TYPE_FULL`; `oomd_select_by_pgscan_rate`; recursive SIGKILL
2. [`src/oom/oomd-manager.c`](https://raw.githubusercontent.com/systemd/systemd/v261/src/oom/oomd-manager.c) — reclaim gate; leaf-candidate walk; swap AND condition
3. [`src/oom/oomd-manager.h`](https://raw.githubusercontent.com/systemd/systemd/v261/src/oom/oomd-manager.h) — timing and threshold constants
4. [`units/user/app.slice`](https://github.com/systemd/systemd/blob/main/units/user/app.slice) — ships `CPUWeight=100` only, no memory settings

**Man pages** (read locally from the installed systemd 261.1)
5. `systemd-oomd.service(8)` — session-scope warning; candidate rules; swap recommendation
6. `systemd.unit(5)` — dash-truncated drop-in search; `type.d/` precedence and the same-filename masking rule
7. [`systemd.resource-control(5)`](https://man.archlinux.org/man/systemd.resource-control.5.en) — `Memory*=`, `ManagedOOM*=`, ancestor-allocation requirement
8. [`oomd.conf(5)`](https://man7.org/linux/man-pages/man5/oomd.conf.5.html), [`systemd-run(1)`](https://man.archlinux.org/man/systemd-run.1.en), [`systemctl(1)`](https://man.archlinux.org/man/systemctl.1.en)

**Kernel**
9. [cgroup-v2](https://docs.kernel.org/admin-guide/cgroup-v2.html) — `memory.{min,low,high,max}`; non-migrating charges
10. [sysctl/vm](https://docs.kernel.org/admin-guide/sysctl/vm.html) — every reserve in §6
11. [PSI](https://docs.kernel.org/accounting/psi.html) — `some` vs `full`
12. [MGLRU](https://docs.kernel.org/admin-guide/mm/multigen_lru.html) — `min_ttl_ms`
13. [LWN: Reconsidering the multi-generational LRU](https://lwn.net/Articles/1060967/) (2026-03-05)
14. [kernelnewbies 6.18](https://kernelnewbies.org/Linux_6.18) — swap-table phase I, kswapd fixes

**nixpkgs / NixOS**
15. [oomd.nix](https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/system/boot/systemd/oomd.nix) — all three sub-options default `false`; per-slice `mkDefault "80%"`
16. [earlyoom.nix](https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/services/system/earlyoom.nix), [nohang.nix](https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/services/system/nohang.nix), [zram.nix](https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/config/zram.nix), [uwsm.nix](https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/programs/wayland/uwsm.nix)
17. [nixpkgs#435587](https://github.com/NixOS/nixpkgs/issues/435587) — "NixOS is bad at handling various memory overload situations", open
18. [home-manager systemd.nix](https://github.com/nix-community/home-manager/blob/master/modules/systemd.nix) — HM slices use raw unit sections, not `sliceConfig`

**Userspace killers**
19. [earlyoom MANPAGE](https://github.com/rfjakob/earlyoom/blob/master/MANPAGE.md) — the AND condition, `-s 100`, `comm` matching
20. [earlyoom#71](https://github.com/rfjakob/earlyoom/issues/71) (zram), [#309](https://github.com/rfjakob/earlyoom/issues/309) (kill cascades), [#6](https://github.com/rfjakob/earlyoom/issues/6) (percentage scaling)
21. [nohang](https://github.com/hakavlad/nohang) + [nohang-desktop.conf.in](https://raw.githubusercontent.com/hakavlad/nohang/master/conf/nohang/nohang-desktop.conf.in)

**Distro policy and case studies**
22. [Fedora: SwapOnZRAM](https://fedoraproject.org/wiki/Changes/SwapOnZRAM) — the 4 G cap and its rationale
23. [Fedora: EnableSystemdOomd](https://fedoraproject.org/wiki/Changes/EnableSystemdOomd) (historical F34 values), [RHBZ 1941170](https://bugzilla.redhat.com/show_bug.cgi?id=1941170) (10%/10s → 50%/20s)
24. [CentOS Stream `10-oomd-per-slice-defaults.conf`](https://gitlab.com/redhat/centos-stream/rpms/systemd/-/raw/c10s/10-oomd-per-slice-defaults.conf) — shipped `80%`, installed into `user/slice.d/`
25. [Fedora: Reserve resources for active user WS](https://fedoraproject.org/wiki/Changes/Reserve_resources_for_active_user_WS) — `uresourced`, 250 MiB capped at 10%, written at all four levels
26. [Phoronix: Ubuntu Drops Swap Kill](https://www.phoronix.com/news/Ubuntu-Drops-Swap-Kill) + [LP#1972159](https://bugs.launchpad.net/ubuntu/+source/systemd/+bug/1972159)
27. [fbtax2 memory controller](https://facebookmicrosites.github.io/cgroup2/docs/memory-controller.html) — `memory.high` thrashing; use `memory.low` to protect
28. [LWN: Resource management for the desktop](https://lwn.net/Articles/829567/) — the session/app/background split
29. [In defence of swap](https://chrisdown.name/2018/01/02/in-defence-of-swap.html)
30. [omarchy#9799](https://github.com/omacom/omarchy/issues/9799) — 2,104 processes killed from one shared scope
31. [AdrienLemaire/nixdots memory.nix](https://github.com/AdrienLemaire/nixdots/blob/main/modules/system/memory.nix), [rnl-dei/nixrnl shell.nix](https://github.com/rnl-dei/nixrnl/blob/main/profiles/ist/shell.nix) — the `user-.slice.d` pattern
32. [uwsm](https://github.com/Vladimir-csp/uwsm), [app2unit](https://github.com/Vladimir-csp/app2unit)

## Methodology

Three parallel research agents (systemd/cgroup mechanism and distro defaults;
userspace killers plus zram/reclaim tuning; NixOS module surface and real-world
configs), then direct verification on this machine: `oomctl`, `systemd-cgls`,
`systemctl show`, `getfattr` on the cgroup xattrs, the `memory.low` chain read
from cgroupfs, the installed `systemd.unit(5)`/`systemd-oomd.service(8)` man
pages, and `src/oom/` fetched at tag `v261` to match the running systemd. The
`app.slice` scope placement and live `set-property` paths in §7–8 were executed
and reverted.

Sub-questions: how oomd decides to act and what it selects; which slice to
monitor and why; what Fedora actually ships now; `MemoryHigh`/`Max`/`Low`/`Min`
semantics and their interaction with swap; kernel memory reserves; protecting
realtime audio and the compositor; earlyoom/nohang/oomd trade-offs; zram sizing
and MGLRU; the NixOS option surface for all of it.
