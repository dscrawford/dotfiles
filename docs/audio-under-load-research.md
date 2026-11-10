# EasyEffects under load: why it breaks, why it never catches up, what to change

*2026-09-02. ~100 sources plus live measurement. High confidence on the mechanism (plugin and host source) and PipeWire/rtkit facts; medium on exact tuning (not benchmarked here).*

## Summary

The mic chain fails under load for three stacked reasons, none of them an
EasyEffects bug:

1. **DeepFilterNet's LADSPA plugin accumulates delay.** Inference runs on a nice-0
   worker; the RT audio thread spin-waits for it. Each underrun adds 10 ms of queue,
   which shrinks by 10 ms only after ~1000 clean cycles with margin; one hiccup
   restarts the count. Bypass doesn't touch the instance; recreation leaks a thread.
2. **The mic ran at half the budget.** The Snowball was pinned to `node.latency = 512`
   with `node.lock-quantum`, giving DFN ~10 ms per cycle while playback had 21–42 ms.
   Mic xruns since boot: **331**; sink: 3.
3. **Nothing kept load away.** `nix-daemon` ran 24 jobs × all cores at normal priority
   on every CPU; rtkit capped PipeWire at RR 20 and kills a thread stalling 200 ms;
   governor `powersave`; the last OOM was a game with 4 G of disk swap.

Applied (§6): a 1024-sample floor for the whole graph, PipeWire's data loop on a
reserved physical core, builds at `batch`/idle-IO with bounded jobs, rtkit at real
priorities with a 5 s stall budget, `performance` governor, zram + systemd-oomd, and
one pre-paid DFN frame. Phase 2 (not applied): move the mic chain into a PipeWire
`filter-chain`.

## 1. What the live system showed

| Fact | Value |
|---|---|
| Mic node xruns since boot / sink | **331** / 3 |
| EE realtime thread | present: `data-loop.0` SCHED_RR 20 (rtkit's ceiling) |
| EE DFN inference thread | `QThread`s, SCHED_OTHER, nice 0 |
| Graph | quantum 1024 @ 48 kHz, min 32, max 2048; mic pinned 512 + lock-quantum |
| PipeWire data loops | last ran on CPUs 22/23/10, allowed 0–23 (unpinned) |
| rtkit | max RT prio 20, RTTIME 200 ms; **no canary demotions this boot** |
| nix-daemon | `max-jobs 24`, `cores 0`, SCHED_OTHER, no CPU set/weight |
| CPU | 12c/24t Ryzen, `amd-pstate-epp`, governor `powersave`, EPP balance_performance |
| Memory | 62 G, 4 G disk swap with 2.3 G used, no zram, oomd active but watching no slices |

## 2. The DeepFilterNet mechanism (read from source)

EasyEffects hosts DFN as a LADSPA plugin (`libdeep_filter_ladspa.so`,
`deep_filter_stereo`), reports a *fixed* 20 ms latency to PipeWire, and has no
reset primitive short of destroy/recreate — its own `clear_data()` is commented
out because "this plugin does not seem to destroy its threads properly"
([deepfilternet.cpp](https://raw.githubusercontent.com/wwmm/easyeffects/master/src/deepfilternet.cpp),
[ladspa_wrapper.cpp](https://raw.githubusercontent.com/wwmm/easyeffects/master/src/ladspa_wrapper.cpp)).
Audio processing itself happens on PipeWire's RT thread
([wwmm, #3659](https://github.com/wwmm/easyeffects/issues/3659)).

Inside the plugin ([ladspa/src/lib.rs](https://raw.githubusercontent.com/Rikorose/DeepFilterNet/main/ladspa/src/lib.rs)):

- inference runs on `thread::spawn` with no priority; audio crosses a mutex-guarded queue;
- `run()` on the RT thread **sleeps in a loop** (~2 ms steps) until the worker has produced enough output — no zeros, no partial output, the RT thread just blocks (this is the dropout);
- on RTF ≥ 1 it logs "Underrun detected", **adds one frame (10 ms) of delay**, pushes zeros; at 1 s of delay it panics ("Please upgrade your CPU");
- delay shrinks by one frame only when >1000 `run()` calls have passed with no underrun **and** RTF < 0.5 on that call **and** delay > the configured minimum — one underrun resets the counter, so 100 ms → 20 ms needs eight consecutive clean windows;
- there is no stop/flush message; recreation leaks the worker thread and the model.

Upstream is dormant: last plugin commit 2023-10-31, last release v0.5.6 2024-08-31, the underrun issue closed stale
([#482](https://github.com/Rikorose/DeepFilterNet/issues/482)). EasyEffects added a
"Reset History" button (8.0.4) that is destroy+recreate — the same operation
as this repo's preset-swap watchdog, with the same thread leak
([changelog](https://wwmm.github.io/easyeffects/community/CHANGELOG.html),
[#3851](https://github.com/wwmm/easyeffects/issues/3851)).

Consequences: prevention beats recovery. Give `run()` a bigger time budget,
keep the worker from being starved, and pre-pay one frame so jitter never
triggers growth. "Min Processing Buffer" is a *floor* on the delay, not a cap.
"Max DF processing threshold" is the only CPU knob.

## 3. PipeWire and scheduling facts that matter

- The quantum is the **lowest** any follower asks for, per driver; an ALSA source and sink are separate drivers with separate cycles ([pw-top(1)](https://docs.pipewire.org/page_man_pw-top_1.html), [scheduling](https://docs.pipewire.org/page_scheduling.html)). A 512 mic + 1024 default meant two budgets, the smaller one on the side doing the NN inference.
- The maintainer's standing diagnosis for load glitches: "when the latency is too low no amount of 'high priority' will avoid glitches"; the fix in every thread is a bigger fixed quantum (1024/2048/4096) ([#2279](https://github.com/wwmm/easyeffects/discussions/2279), [#4722](https://github.com/wwmm/easyeffects/issues/4722)).
- PulseAudio clients (games, browsers, Discord) are clamped by `pulse.min.quantum` (default 256/48000) — without a floor a game pulls the graph to 5 ms cycles ([module-protocol-pulse](https://docs.pipewire.org/page_module_protocol_pulse.html)).
- rtkit: max priority 20, `RLIMIT_RTTIME` 200 ms, SCHED_RR forced, canary demotes all RT threads on overload ([rtkit-daemon.c](https://raw.githubusercontent.com/heftig/rtkit/master/rtkit-daemon.c), [README](https://github.com/heftig/rtkit/blob/master/README)). PipeWire wants 88 and was clamped to 20 ([module-rt](https://docs.pipewire.org/page_module_rt.html)). Upstream's own recommendation when using rtkit: `--scheduling-policy=FIFO --our-realtime-priority=89 --max-realtime-priority=88 --min-nice-level=-19` ([Performance-tuning](https://gitlab.freedesktop.org/pipewire/pipewire/-/wikis/Performance-tuning)).
- RT beats CFS unconditionally, and PREEMPT_LAZY (NixOS 6.18) "works as full preemption for RR/FIFO" ([LWN](https://lwn.net/Articles/994322/)). What still hurts an RT thread under a build: the SMT sibling ([kernel cpu-isolation](https://docs.kernel.org/admin-guide/cpu-isolation.html), [linuxaudio wiki](https://wiki.linuxaudio.org/wiki/system_configuration)), memory/LLC bandwidth (which NN inference is heavy on), lower all-core clocks, and the RT thread blocking on a nice-0 worker — which is exactly DFN's design.
- cgroup v2 `cpu.weight`/`cpu.max` **do not apply to RT threads**; NixOS kernels have `RT_GROUP_SCHED=n`, so weights are safe and only affect the non-RT parts ([cgroup-v2](https://docs.kernel.org/admin-guide/cgroup-v2.html), [common-config.nix](https://raw.githubusercontent.com/NixOS/nixpkgs/master/pkgs/os-specific/linux/kernel/common-config.nix)). `AllowedCPUs` is a cpuset and applies to every class — the one lever that also relieves the SMT sibling.
- `nice` only ranks threads within the same autogroup on a NixOS kernel (`SCHED_AUTOGROUP=y`); cgroup weight is what ranks services against each other ([sched(7)](https://man7.org/linux/man-pages/man7/sched.7.html), [nixpkgs discourse](https://discourse.nixos.org/t/can-i-set-the-nice-level-for-nix-build-processes/10596)).
- `nix.daemonCPUSchedPolicy`: `idle` drops builds to ~1% of a core under any CFS load and the option text warns it "may starve crucial configuration updates"; `batch` keeps them running with a wakeup penalty ([nix-daemon.nix](https://raw.githubusercontent.com/NixOS/nixpkgs/master/nixos/modules/services/system/nix-daemon.nix), [LWN on SCHED_IDLE](https://lwn.net/Articles/805317/)). Default fan-out is `max-jobs auto × cores 0` = 24 × 24, which the Nix manual itself calls degraded by context switching ([cores vs jobs](https://nix.dev/manual/nix/2.24/advanced-topics/cores-vs-jobs)).
- RT tasks default to `uclamp.min = 1024`, but on `amd-pstate-epp` the boost decision is the firmware's; audio guides converge on the `performance` governor ([sched-util-clamp](https://docs.kernel.org/scheduler/sched-util-clamp.html), [ArchProAudio](https://raw.githubusercontent.com/chmaha/ArchProAudio/main/README.md)).
- Memory: `memory.low` only holds if every ancestor grants it ([systemd.resource-control](https://man.archlinux.org/man/systemd.resource-control.5.en)); NixOS enables `systemd-oomd` but watches no slices by default ([oomd.nix](https://raw.githubusercontent.com/NixOS/nixpkgs/master/nixos/modules/system/boot/systemd/oomd.nix)); zram is "an order of magnitude faster than drive based swap" and the NixOS wiki pairs it with oomd ([Fedora](https://fedoraproject.org/wiki/Changes/SwapOnZRAM), [NixOS wiki](https://wiki.nixos.org/wiki/Swap)).

## 4. What not to do

- Chase lower latency (512 mic, `disable-batch`, `disable-tsched`, 256 quantum). The maintainer's diagnosis is the opposite.
- `threadirqs` without `rtirq`: it puts every driver's IRQ thread at FIFO 50, above rtkit's 20 ([manage.c](https://raw.githubusercontent.com/torvalds/linux/master/kernel/irq/manage.c)).
- `isolcpus`/`nohz_full` on a gaming desktop: kernel docs call them inflexible and invasive; `nohz_full` needs one runnable task per CPU ([no_hz](https://docs.kernel.org/timers/no_hz.html)).
- Rely on `CPUWeight` to protect the RT thread (it can't); rely on the watchdog to fix DFN (each reset leaks a thread).
- `mem.mlock-all` with the default 8 MiB memlock; `sched_rt_runtime_us = -1`; irqbalance ([Arch pro-audio](https://wiki.archlinux.org/title/Professional_audio)).
- PREEMPT_RT / `-rt` kernel for a 21 ms quantum with an NVIDIA module — unnecessary and risky ([declension](https://declension.net/posts/2022-06-19-kernels-pipewire-and-xruns/)).

## 5. Phase 2 (recommended, not applied): move the mic chain into a PipeWire filter-chain

Same DFN plugin, three real differences: the inference worker inherits
PipeWire's nice −11 instead of EE's 0; the quantum can be pinned per node
(`node.force-quantum`, `node.latency`); recovery is `systemctl --user restart
filter-chain` with no thread leak, no GUI, no watchdog
([module-filter-chain](https://docs.pipewire.org/page_module_filter_chain.html),
upstream [filter-chain.service](https://raw.githubusercontent.com/PipeWire/pipewire/master/src/daemon/systemd/user/filter-chain.service.in),
upstream [DFN mono config](https://raw.githubusercontent.com/Rikorose/DeepFilterNet/main/ladspa/filter-chain-configs/deepfilter-mono-source.conf)).
Echo cancellation moves to `libpipewire-module-echo-cancel` in `monitor.mode`
(no virtual sink, matching `processAllOutputs=false`)
([module-echo-cancel](https://man.archlinux.org/man/libpipewire-module-echo-cancel.7.en)).

Verified locally: `pkgs.deepfilternet` 0.5.6 ships `libdeep_filter_ladspa.so`
with labels `deep_filter_mono`/`deep_filter_stereo`; `pkgs.rnnoise-plugin`
1.10; `pkgs.lsp-plugins` 1.2.34 ships a LADSPA bundle with `gate_mono` for the
gate stage; `services.pipewire.extraLadspaPackages` exists; the
`filter-chain.service` unit is already installed with `LADSPA_PATH`. Note
PipeWire ≥ 1.6.3 refuses absolute plugin paths outside the search path, so the
NixOS option must be used ([discourse](https://discourse.nixos.org/t/pipewire-rnnoise-module-wont-work/58975)).

Cost: losing the EasyEffects GUI for the mic, and the gate/AEC settings become
config text. If DFN still misbehaves there, RNNoise (`noise_suppressor_mono`)
is stateless per 10 ms frame and cannot accumulate, at a quality cost.

## 6. What was changed in this repo

`hosts/local/audio.nix`
- rtkit: FIFO, our prio 89, max 88, min nice −19, RTTIME 5 s.
- PipeWire: `default.clock.quantum 1024`, `min-quantum 1024`, `max-quantum 2048`; data loop `data-loop.0` pinned to CPUs 11 and 23 (one physical core and its SMT sibling); `pulse.min.quantum`/`pulse.min.req` 1024/48000. `module-rt` is not re-declared: the stock config already asks for 88 (clients 83) and sizes `RLIMIT_RTTIME` from rtkit, so the rtkit change alone lifts both.
- Mic rule: `node.latency 1024/48000`, `node.lock-quantum` removed.

`hosts/local/priority.nix` (new)
- `nix.daemonCPUSchedPolicy batch`, IO class idle prio 7, `max-jobs 4`; `nix-daemon` `AllowedCPUs 0-10,12-22`, `CPUWeight 20`, `IOWeight 20`, `OOMScoreAdjust 500`, `MemoryHigh 70%`.
- `powerManagement.cpuFreqGovernor performance`; gamemode `renice 10`.
- zram 50 % zstd with the Pop!_OS sysctls; oomd on root/system/user slices at 60 %.
- `MemoryLow` chain user.slice → user@ → session.slice → pipewire/wireplumber/pipewire-pulse (`asDropin`), `CPUWeight 1000`, `OOMScoreAdjust −900`, `ManagedOOMPreference avoid`.

`shared/easyeffects.nix`
- DFN `min-processing-buffer 0 → 1`.

Cost you are accepting: ~16 ms more audio latency for PulseAudio clients that
asked for 256; builds lose two of 24 threads and run at weight 20 when
contended (near-zero cost on an idle desktop); performance governor draws more
power at idle.

## 7. How to verify

1. Rebuild, re-login (data-loop pinning and rtkit take effect at PipeWire start).
2. `ps -eLo tid,cls,rtprio,comm | grep data-loop` — expect `FF 88` (server) and `FF 83` (EE); `grep Cpus_allowed_list /proc/<tid>/status` — expect `11,23`.
3. `pw-metadata -n settings | grep quantum` — min 1024.
4. `deploy-nodes --build-only` while talking into the mic; watch `pw-top -b -n 30 | grep -E 'BLUE|deepfilternet'` — the mic ERR column should not increment, and the DFN row's B/Q should stay well under 0.8.
5. If the driver row (the Snowball) still xruns while followers don't, it is ALSA timing: try `api.alsa.period-size 1024`, then `api.alsa.headroom 8192` ([PipeWire troubleshooting](https://gitlab.freedesktop.org/pipewire/pipewire/-/wikis/Troubleshooting)).

