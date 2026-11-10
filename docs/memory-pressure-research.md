# Reserving memory for stability: why a runaway app freezes this desktop

*2026-09-18. ~45 sources (systemd v261 source, kernel docs, man pages, distro policy)
plus live measurement. High confidence on mechanism and diagnosis; medium on numeric
tuning (freeze not reproduced).*

## Summary

Memory can be reserved, but the right knob is a cgroup limit on the apps, not a kernel
reserve, and the freeze isn't a missing knob: **every graphical process lives in one
cgroup.**

`hosts/local/priority.nix` already has zram, four reclaim sysctls, systemd-oomd on all
three slices, `MemoryLow` for audio, and `ManagedOOMPreference=avoid` on PipeWire. Five
problems, all verified live:

1. **oomd's likeliest victim is the whole desktop.** sway, waybar, mako, swaybg,
   Xwayland, Emacs and Firefox (55 processes, 7.2 of 8.3 G in use) share the leaf
   `session-3.scope`; oomd kills a leaf recursively.
2. **The `MemoryLow` chain breaks** at `user-1000.slice` (`memory.low = 0`), voiding
   PipeWire's 128 M.
3. **`DefaultMemoryPressureLimit = "60%"` is dead**; every cgroup runs at 80%.
4. **Nothing watches swap** despite 35 G of it.
5. **oomd fires on PSI `full`, not `some`**, behind a 30 s reclaim-activity gate.

Fix in order: put apps in their own cgroups, cap them, repair the protection chain.
Kernel `vm.*` reserves are the wrong tool (§6).

## 1. Live system

systemd 261.1, kernel 6.18.44, 62 Gi RAM, 31.4 G zram (prio 5) + 4 G disk swap (prio -2):

| Fact | Value |
|---|---|
| `session-3.scope` | **7.2 G / 55 procs**, **leaf**, `memory.oom.group` 0, no `oomd_avoid`/`_omit` xattr |
| `user-1000.slice` `memory.low` | **0** ← chain break |
| oomd monitored | `/`, `/system.slice`, `/user.slice`, `app.slice`, `background.slice` at **80% / 30 s** |
| oomd swap-monitored | **none** |
| `session.slice` monitored | **no** (§5) |
| `kernel.sysrq` | 16 |

```
user-1000.slice
├─user@1000.service
│ ├─session.slice   dbus-broker, pipewire, wireplumber, pipewire-pulse, portals
│ ├─app.slice       ollama, ssh-agent, wivrn, xdg-desktop-portal-{gtk,wlr}, obex
│ └─init.scope
└─session-3.scope   greetd, sway, waybar, mako, swaybg, Xwayland, emacs,
                    firefox ×8, easyeffects, … 55 processes
```

`app.slice` holds only user services, so a `MemoryHigh` there wouldn't touch Firefox.

## 2. One cgroup for the session is the bug

`systemd-oomd.service(8)`: if you monitor `user.slice` or `user-$UID.slice`, have
programs managed by the user manager to "avoid a situation where memory intensive tasks
trigger systemd-oomd to kill everything under the cgroup". `priority.nix` sets
`enableUserSlices = true`. GNOME/KDE launch components as user units; sway `exec`s them,
so every `exec`/`bindsym … exec` in `shared/sway/config.nix` (`mako`, `easyeffects`,
`foot`, `wmenu-run`, `firefox`) lands in `session-3.scope`.

From `src/oom/` at `v261`: `recursively_get_cgroup_context()` (`oomd-manager.c:291`)
descends to **leaves** (stopping at `memory.oom.group=1`); candidates rank by pgscan rate
(`oomd-util.c:586`); the kill is `recurse = true`. `session-3.scope` is the biggest
unprotected leaf, so it goes first with all 55 processes. Upstream example:
[omarchy#9799](https://github.com/omacom/omarchy/issues/9799), 2,104 processes killed from
one scope.

## 3. oomd fires late, or not at all

- **PSI `full`** (`oomd-util.c:684`): every non-idle task stalled at once, "considered to
  be thrashing" ([PSI](https://docs.kernel.org/accounting/psi.html)). Effective trigger:
  `full` avg10 > 80% for 30 s.
- **Reclaim gate** (`oomd-manager.c:591`): no kill unless `pgscan` rose within
  `RECLAIM_DURATION_USEC`. An all-anonymous working set with nothing to reclaim can
  livelock past oomd.

| Constant (`oomd-manager.h`) | Value |
|---|---|
| `MEM_PRESSURE_INTERVAL_USEC` | 1 s |
| `SWAP_INTERVAL_USEC` | 0.15 s |
| `DEFAULT_MEM_PRESSURE_DURATION_USEC` | 30 s |
| `DEFAULT_MEM_PRESSURE_LIMIT_PERCENT` | 60 |
| `DEFAULT_SWAP_USED_LIMIT_PERCENT` | 90 |
| `RECLAIM_DURATION_USEC` | 30 s |
| `POST_ACTION_DELAY_USEC` | 15 s |

Swap action (`oomd-manager.c:478`) needs MemAvailable < 10% **and** swap free < 10%, but
nothing sets `ManagedOOMSwap=kill`, so it's unreachable. Known upstream:
[systemd#33486](https://github.com/systemd/systemd/issues/33486),
[#25596](https://github.com/systemd/systemd/issues/25596),
[RHBZ 2248071](https://bugzilla.redhat.com/show_bug.cgi?id=2248071).

## 4. Config bugs in `priority.nix`

**4.1 60% never binds.** NixOS's `enable*Slice` options emit per-slice
`ManagedOOMMemoryPressureLimit = mkDefault "80%"`
([oomd.nix](https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/system/boot/systemd/oomd.nix)),
which beats the daemon default. Override per slice.

**4.2 `MemoryLow` chain.** `systemd.resource-control(5)`: protection needs allocations on
all ancestors.

```
/user.slice                                      low=512M
/user.slice/user-1000.slice                       low=0      ← break
/user.slice/…/user@1000.service                   low=512M
/user.slice/…/session.slice                       low=512M
/user.slice/…/session.slice/pipewire.service      low=128M
```

`priority.nix` sets `user.slice` and `user@.service`, not the per-UID slice. Use the
dash-truncated drop-in (`systemd.unit(5)` searches `foo-.service.d/`):

```nix
systemd.slices."user-" = {
  overrideStrategy = "asDropin";     # → /etc/systemd/system/user-.slice.d/overrides.conf
  sliceConfig.MemoryLow = "2G";
};
```

**4.3 No swap protection.** The NixOS module never emits `ManagedOOMSwap=` (`auto` in
`systemctl show` means off). Don't just enable it: Fedora and Ubuntu retreated from
swap-kill on `-.slice` after it killed Firefox during harmless swapping
([Phoronix](https://www.phoronix.com/news/Ubuntu-Drops-Swap-Kill)). Bound the window with
`MemorySwapMax=` instead.

## 5. A drop-in name collision unmonitors `session.slice`

`systemd.unit(5)`: a `type.d/` drop-in applies only if no higher-precedence drop-in has the
same name. NixOS names all generated drop-ins `overrides.conf`; `enableUserSlices` writes
`/etc/systemd/user/slice.d/overrides.conf`, and `systemd.user.slices.session` writes
`session.slice.d/overrides.conf`, which masks it:

```
session.slice  DropInPaths=…/session.slice.d/overrides.conf   ManagedOOMMemoryPressure=auto
app.slice      DropInPaths=…/slice.d/overrides.conf           ManagedOOMMemoryPressure=kill
```

Accidentally good for audio, but **any `systemd.user.slices.<X>` override silently
disables oomd for `<X>`**: restate `ManagedOOM*` in it. (`ManagedOOMPreference=avoid`
works: `user.oomd_avoid="1"` is set on pipewire and wireplumber.)

## 6. Kernel reserves: mostly wrong tool

[sysctl/vm](https://docs.kernel.org/admin-guide/sysctl/vm.html):

| sysctl | Verdict |
|---|---|
| `vm.admin_reserve_kbytes` (8192) | buys an ssh/kill during exhaustion; raise to ~256 M |
| `vm.user_reserve_kbytes` (131072) | **inert** under overcommit mode 0 |
| `vm.min_free_kbytes` (67584) | marginal; too high triggers OOM |
| `vm.watermark_scale_factor` | the useful one: reclaim in kswapd, not the foreground app; already 125 |
| `vm.overcommit_memory=2` | hard cap, breaks Electron/JVM/Go/Chromium; not for a desktop |

None bound resident memory. Only `memory.max` does.

## 7. Knobs that bound an app

| systemd | cgroup | Semantics |
|---|---|---|
| `MemoryMin=` | `memory.min` | hard protection; unmeetable → OOM killer |
| `MemoryLow=` | `memory.low` | best-effort protection |
| `MemoryHigh=` | `memory.high` | throttle + reclaim; never OOM-kills |
| `MemoryMax=` | `memory.max` | hard limit; OOM kill **inside the cgroup** |
| `MemorySwapMax=` | `memory.swap.max` | bounds the thrash window |

`MemoryMax` reserves the rest by construction (apps ≤ 50 of 62 G leaves 12 G), and on trip
the kernel kills by `oom_badness` within the cgroup: the 20 G Firefox process dies, sway
survives. Caveats:

- `MemoryHigh` alone can swap forever at the boundary
  ([fbtax2](https://facebookmicrosites.github.io/cgroup2/docs/memory-controller.html));
  pair it with `MemoryMax` and `MemorySwapMax`.
- Charges don't migrate with the process, so the limit must exist at app start.
- Audio: `MemoryLow` on the slices plus a small, always-meetable `MemoryMin` (~128 M) on
  `pipewire.service`.

## 8. Fixing process placement

Both are in the pinned nixpkgs: **uwsm 0.26.6**, **app2unit 1.4.4**.

- **A: `app2unit`** (incremental, low risk). Wrapped `foot`/`firefox`/`wmenu-run` become
  `app-*.scope` under `app.slice`; terminal children inherit the terminal's scope. Verified
  ad hoc here (then reverted):

  ```bash
  systemd-run --user --scope --slice=app.slice -p MemoryHigh=8G -p MemoryMax=12G firefox
  ```

- **B: `programs.uwsm.enable`** (structural). `app-graphical`/`background-graphical`/
  `session-graphical` slices, `uwsm app -s a|b|s -t scope|service --`, and it reaches
  `graphical-session.target` (fixing the tray/autostart workaround). Forces dbus-broker and
  changes the greetd command; untested here.

Do A first; B when revisiting `graphical-session.target`.

## 9. Per-process killers

| | Trigger | Granularity | Fires |
|---|---|---|---|
| systemd-oomd | PSI `full` + active reclaim | cgroup, recursive | very late (§3) |
| earlyoom | free RAM **AND** free swap | process | early; blind to refault thrash |
| nohang | mem **OR** swap **OR** zram **OR** PSI | process, regex badness | configurable |

- **earlyoom's AND:** 35 G idle swap disarms it; use `-s 100,100` and absolute KiB
  (`-M`/`-S`) ([MANPAGE](https://github.com/rfjakob/earlyoom/blob/master/MANPAGE.md)).
  `--avoid`/`--prefer` match 15-char `comm`.
- **nohang:** NixOS module `services.nohang` (`configPath = "desktop"`), self-limited unit;
  desktop preset uses `full_avg10` PSI 40/90, mem 5%/2%, zram 55%, protects desktop
  components, SIGTERM before SIGKILL. No built-in SIGSTOP mode.
- Don't overlap two killers' thresholds.
- `OOMScoreAdjust=-900` protects against earlyoom's default selection, not `--sort-by-rss`
  and not oomd.

## 10. zram is sized aggressively

`memoryPercent = 50` → 31.4 G. Fedora caps at `min(RAM/2, 4096 MiB)`: zram allocates ~½ the
page-out rate, and big devices thrash CPU-bound, so "better to just oom"
([SwapOnZRAM](https://fedoraproject.org/wiki/Changes/SwapOnZRAM)). Full at 2–3:1 it holds
10–15 G of RAM, with `swappiness = 150` pushing eagerly.

- MGLRU is on (`lru_gen/enabled` = `0x0007`); its anon/file imbalance makes "swappiness
  tuning … ineffective" ([LWN 2026-03](https://lwn.net/Articles/1060967/)). `min_ttl_ms =
  1000` targets desktop jank, off by default.
- `watermark_boost_factor = 0` / `watermark_scale_factor = 125` come from
  [Pop!_OS #163](https://github.com/pop-os/default-settings/pull/163): sound direction,
  folklore numbers.

## 11. Recommendations (not applied)

**1. Stop oomd killing the session.** Fix placement (§8) or exclude the scope; and close
the chain:

```nix
systemd.slices."user-" = {
  overrideStrategy = "asDropin";
  sliceConfig.MemoryLow = "2G";
};
```

**2. Reserve memory** once apps are in `app.slice`, restating `ManagedOOM*` (§5):

```nix
systemd.user.slices.app.sliceConfig = {
  MemoryHigh = "44G";      # ~70%
  MemoryMax  = "50G";      # ~80%, cgroup-internal OOM kill
  MemorySwapMax = "8G";
  ManagedOOMMemoryPressure = "kill";
  ManagedOOMMemoryPressureLimit = "50%";
  ManagedOOMMemoryPressureDurationSec = "10s";
};
```

**3. Real audio protection:** `MemoryMin = "128M"` on `pipewire.service` on the repaired
chain.

**4. Per-process second layer** if 1 is deferred: `services.nohang`, or

```nix
services.earlyoom = {
  enable = true;
  extraArgs = [
    "-M" "3145728" "-S" "1572864"
    "-s" "100,100"
    "--avoid" "^(sway|Xwayland|waybar|mako|pipewire|wireplumber|systemd|dbus-broker)$"
    "--prefer" "^(firefox|\\.firefox-wrapped|chromium|electron|node|ollama)$"
    "-p"
  ];
};
```

and set `user.slice`'s oomd action to `"auto"` so they don't fight (as
[nixdots](https://github.com/AdrienLemaire/nixdots/blob/main/modules/system/memory.nix) does).

**5. Housekeeping:** drop `DefaultMemoryPressureLimit` or set it per slice;
`zramSwap.memoryPercent = 25`; `vm.admin_reserve_kbytes = 262144`;
`kernel.sysrq = 244` (`watchdog-sysrq-research.md`, still unapplied).

Verify (should kill only the scope):

```bash
systemd-run --user --scope --slice=app.slice -p MemoryMax=4G \
  stress-ng --brk 2 --stack 2 --bigheap 2 --timeout 90s
oomctl
journalctl -u systemd-oomd   # "and there was reclaim activity"
```

## Gaps

- No freeze reproduced; the 2026-08-30 OOM (`priority.nix`) predates journal retention
  (oldest boot 2026-09-07), and no retained boot has OOM or oomd kills.
- uwsm + greetd + sway untested.
- Thresholds (44/50 G, 50%/10 s) are starting points.
- Fedora's shipped oomd values came from CentOS Stream 10
  ([10-oomd-per-slice-defaults.conf](https://gitlab.com/redhat/centos-stream/rpms/systemd/-/raw/c10s/10-oomd-per-slice-defaults.conf):
  80%, in `user/slice.d/`); Fedora's wiki still shows F34 values.
- Nothing upstream ties PipeWire xruns directly to memory pressure; the chain is indirect
  (unmet `RLIMIT_MEMLOCK` → data-loop page fault → xrun).
