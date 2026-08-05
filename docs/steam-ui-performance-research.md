# Steam UI & Big Picture Performance on NixOS/Wayland: Research Report

*Generated: 2026-08-04 | Sources: 22 | Confidence: Medium-High*

Scope: optimizing the Steam desktop UI and Big Picture Mode (BPM) on this machine —
NixOS 26.11, sway 1.12 / wlroots 0.20.2, NVIDIA 610.43.02 proprietary, RTX 3080 Ti,
three outputs (3840x2160@60, 3440x1440@165, 2560x1440@165), Steam build 1785799196.

Every recommendation below was checked against this machine's actual state rather than
applied generically. Where the internet's standard advice does **not** apply here, that is
called out explicitly — those sections are the most valuable part of this report.

---

## Executive Summary

The single most-recommended fix on the internet for slow Steam UI / Big Picture on Linux —
forcing CEF back onto a working GPU path with `-cef-force-glx` or disabling it with
`-cef-disable-gpu` — **does not apply to this machine**. Steam's CEF is already
GPU-accelerated here; that was verified three independent ways. Most forum advice targets
that failure mode, so it can be skipped wholesale.

The genuine wins on this configuration are compositor-side, not Steam-side: restoring
wlroots direct scan-out (done — see the local.nix change), and, if BPM is still not smooth,
moving BPM to gamescope with the WSI layer enabled. Steam-side, the only real lever is the
Library low-performance/low-bandwidth settings and reducing how many CEF views are open.

---

## 1. What Is Already Ruled Out On This Machine

### 1.1 CEF is NOT falling back to software rendering

The dominant Linux failure mode: Chromium's GPU process fails EGL init on X11
("Invalid visual ID requested"), Steam silently disables UI GPU acceleration, and the whole
UI — Big Picture worst of all — falls back to software rasterization. The fix circulated
everywhere is `STEAM_RUNTIME=1 steam -no-cef-sandbox -cef-force-glx`, confirmed working by
justawesome360 on 2026-02-01 ([issue #12694](https://github.com/ValveSoftware/steam-for-linux/issues/12694)).

**This is not happening here.** Three independent checks:

| Check | Result |
|---|---|
| `libGLX_nvidia.so.610.43.02` + `libnvidia-glcore` mapped in every steamwebhelper process | present |
| `nvidia-smi` per-process VRAM | steamwebhelper 186 MiB + 404 MiB |
| `htmlcache/GrShaderCache` (Skia GL shader cache — only written when GPU rasterization is live) | 6.2 MB, 95 files, mtime 2026-08-04 18:42 |

A live, growing `GrShaderCache` is the decisive one: Skia only populates it when rasterizing
on the GPU. So `-cef-force-glx` is a no-op here and `-cef-disable-gpu` would be an active
downgrade.

Related but also not applicable: [#10561](https://github.com/ValveSoftware/steam-for-linux/issues/10561)
(black UI without `-cef-disable-gpu`) and
[CachyOS #1376](https://github.com/CachyOS/CachyOS-PKGBUILDS/issues/1376) (black screen on
Niri) are both *correctness* failures, not the *slowness* being investigated.

### 1.2 The Steam client is already new enough

The 2026-07-21 stable client fixed a steamwebhelper crash that occurred specifically when
hardware acceleration was enabled on NVIDIA GPUs
([9to5Linux](https://9to5linux.com/new-steam-client-update-improves-nvidia-gpu-hardware-acceleration-on-linux),
[Neowin](https://www.neowin.net/news/steam-client-beta-update-fixes-crashes-on-linux-when-using-nvidia-gpus/),
[GamingOnLinux](https://www.gamingonlinux.com/2026/07/fresh-stable-steam-update-out-with-updates-for-steam-machine-steam-controller-remote-play-and-more/)).
Local build id 1785799196 dates from August 2026, so this is already included. Note this fixed
*crashes*, not UI throughput — no Big Picture performance fix was listed in that changelog.

### 1.3 GPU selection is correct

Steam's own `GpuTopology` query reports `default_gpu_id: 1`, and id 1 is the RTX 3080 Ti
(llvmpipe is ids 2 and 3). `vulkaninfo` independently enumerates the NVIDIA card as GPU0.
No llvmpipe fallback is in play.

---

## 2. The Confirmed Local Root Cause: Direct Scan-Out

Covered in detail in the `hosts/local/local.nix` comment; summarized here because it is the
highest-impact item and the research corroborates the mechanism.

`WLR_NO_HARDWARE_CURSORS=1` was set globally. In wlroots 0.20.2
(`types/output/output.c:1002`):

```c
bool wlr_output_is_direct_scanout_allowed(struct wlr_output *output) {
	// If the output has at least one software cursor, reject direct scan-out
```

Forcing software cursors therefore disables zero-copy direct scan-out on every output,
permanently. Fullscreen surfaces — Big Picture above all — lose the ability to be flipped
straight to the display and instead take a full compositor render pass plus a buffer copy
every frame.

This matters more here than on a typical setup: three outputs, 9840x2399 of combined desktop,
two panels at 165 Hz.

Zero-copy direct scan-out for fullscreen windows is exactly the path Sway gained via
linux-dmabuf surface feedback ([Phoronix on Sway 1.7-rc1](https://www.phoronix.com/news/Sway-1.7-rc1)),
and the same principle is why fullscreen bypass matters on other compositors
([KWin direct scan-out discussion](https://www.reddit.com/r/linux_gaming/comments/u6dckj/psa_disabling_the_compositor_leads_to_butter/)).

### 2.1 The one risk to watch — hardware cursors on NVIDIA

This is contested in the sources and is the reason the change is documented with a revert
path.

**Against** — NVIDIA's own explanation of the original bug: "wlroots allocates a buffer in
system memory and then tries to use it as the surface for the cursor. NVIDIA dGPUs can only
display surfaces that are in video memory," producing an invisible cursor
([NVIDIA developer forums](https://forums.developer.nvidia.com/t/hardware-cursor-is-not-working-on-wayland-drm-sessions/261853)).
Recent NVIDIA-on-sway setup guides still ship the variable by default, e.g.
[justaguylinux/sway-setup](https://codeberg.org/justaguylinux/sway-setup/wiki/NVIDIA):
"the one most people end up needing — without it the cursor goes invisible on NVIDIA on a lot
of configurations," and [crispyricepc/sway-nvidia](https://github.com/crispyricepc/sway-nvidia/blob/main/wlroots-env-nvidia.sh).

**For** — the driver-side problem has been resolved at least for the sibling wlroots-derived
stack: "Starting from Hyprland 0.4x NVIDIA hardware cursor issues is solved, there is no need
to pass WLR_NO_HARDWARE_CURSORS; also this option is deprecated now"
([dotfiles issue #327](https://gitlab.com/stephan-raabe/dotfiles/-/issues/327)). Most of the
"you still need it" guidance predates driver 600-series and wlroots 0.20.

**Verdict:** genuinely uncertain, must be settled empirically. The test is trivial — log in
and look at the cursor. If it is invisible or corrupt, restore the single line. Everything
else in this report is independent of that outcome.

### 2.2 A historical caveat, probably stale

An Arch forum thread reports that on sway with `nvidia_drm`, fullscreen direct scan-out
capped FPS at half the refresh rate, workaround being to disable scan-out
([bbs.archlinux.org #270454](https://bbs.archlinux.org/viewtopic.php?id=270454)). A separate
report notes XWayland texture shimmer fixed by `sway -Dnoscanout`. Both are old (driver 4xx
era). Flagged only so the symptom is recognizable — if BPM or games become *worse* rather
than better after the change, `sway -Dnoscanout` isolates scan-out as the cause.

---

## 3. Corroborating Evidence That Big Picture Is Compositor-Bound

Two independent reports point at the compositor rather than Steam:

- [Issue #11255](https://github.com/ValveSoftware/steam-for-linux/issues/11255) — "Massive Lag
  & Corruption in Big Picture mode Under latest Nvidia Driver, **Works correctly under
  Gamescope**." The reporter measured "framerate is much much improved" inside gamescope. The
  issue is closed without a root-cause explanation; it is a repeat of #8918.
- In the same thread, a user found that on **Wayland specifically**, enabling "GPU accelerated
  rendering in web views" fixed Big Picture's performance — the opposite of the usual X11
  advice to disable it. (This setting is already enabled here, per §1.1.)

Valve has attempted Big Picture NVIDIA fixes repeatedly with limited success
([GamingOnLinux, 2023](https://www.gamingonlinux.com/2023/05/valve-tries-to-improve-big-picture-mode-on-linux-for-nvidia-gpus/),
[issue #9263](https://github.com/ValveSoftware/steam-for-linux/issues/9263)). Treating BPM-on-
NVIDIA-desktop-compositor as a long-standing unfixed problem, and routing around it, is better
supported than waiting for a client fix.

---

## 4. Actionable Options, Ranked

### 4.1 Steam Settings — free, no rebuild

Settings → Library: enable **Low Performance Mode** and **Low Bandwidth Mode**; set library
display size to **small**. These cut animation and image work in the Panorama UI and are the
only officially exposed UI-cost levers
([community guidance](https://steamcommunity.com/discussions/forum/10/2577696996230698194/),
[GamingOnLinux forum](https://www.gamingonlinux.com/forum/topic/4129/)). Long-standing CPU
burn from library animations is documented in
[issue #6630](https://github.com/ValveSoftware/steam-for-linux/issues/6630).

Do **not** disable "GPU accelerated rendering in web views" — that is X11-era advice, it is
working here, and on Wayland it is reported to help BPM rather than hurt (§3).

### 4.2 Reduce open CEF views — free, worth testing

Sway's tree currently holds three Steam CEF windows — main, Friends List, and a chat window —
all sized 3440x1370 and stacked in one tabbed container. Two zygote-forked renderers were
sampled at 10.1% and 12.8% CPU while Steam was merely in the background. Under XWayland with
`-use_xcomposite_workaround`, Steam's windows are redirected offscreen, so Chromium's
occlusion detection — which normally throttles hidden views to near-zero — may not fire.

Closing the Friends List and chat windows when not needed is a zero-cost experiment.
*Confidence: medium* — the CPU figures are measured, the occlusion-detection explanation is
inferred and untested.

### 4.3 Gamescope for Big Picture — the strongest structural option

Already half-configured: `programs.gamescope.enable` and
`programs.steam.gamescopeSession.enable` are both on, giving a "Steam (gamescope)" entry at
the greeter that runs BPM natively and skips XWayland entirely.

The missing piece for NVIDIA was the WSI layer, now applied in `hosts/local/steam.nix`:

```nix
programs.gamescope.enableWsi = true;
```

gamescope-wsi is a Vulkan WSI layer that lets gamescope talk to NVIDIA's Vulkan stack without
going through XWayland ([Botmonster](https://botmonster.com/self-hosting/gamescope-desktop-linux-hdr-vrr-fps-limiting-steam/),
[ArchWiki: Gamescope](https://wiki.archlinux.org/title/Gamescope)). NVIDIA also needs
`nvidia-drm.modeset=1` — already satisfied via `hardware.nvidia.modesetting.enable = true`.

Caveat: gamescope and NVIDIA remain an imperfect pairing — it is the reason cited for SteamOS's
delayed NVIDIA support ([TechTimes](https://www.techtimes.com/articles/318939/20260623/steamos-nvidia-support-confirmed-valve-has-growing-team-amd-builds-work-now.htm)).
Nested gamescope on a Wayland desktop also has known issues with fullscreen child windows
including embedded Steam ([gamescope #1356](https://github.com/ValveSoftware/gamescope/issues/1356)),
so the greeter session is the better path than nesting inside sway.

### 4.4 Do NOT reflexively enable `capSysNice`

Many NixOS gaming configs set `programs.gamescope.capSysNice = true` for realtime priority.
On NVIDIA this has an open report of total breakage: setting `CAP_SYS_NICE` causes
`vkCreateDevice failed (VkResult: -3)` → "Failed to initialize Vulkan"
([gamescope #521](https://github.com/ValveSoftware/gamescope/issues/521), open since 2022,
last tested there on driver 515). Whether it still bites on 610 is unknown. If tried, test it
in isolation and be ready to revert. Currently `false` — leaving it alone is defensible.

### 4.5 `WLR_RENDERER=vulkan` — plausible, but two specific hazards here

sway currently runs the default GLES2 renderer (no `WLR_RENDERER` set). The Vulkan renderer is
widely recommended for NVIDIA to avoid flickering and is described as "a more principled
solution" ([sway-nvidia](https://github.com/crispyricepc/sway-nvidia/blob/main/wlroots-env-nvidia.sh)).
`libwlroots-0.20.so` exports `wlr_vk_renderer_create_with_drm_fd`, so the build supports it.

Two reasons for caution specific to this machine:

1. Sway has historically failed to start entirely under `WLR_RENDERER=vulkan` on NVIDIA with
   `ERROR_LAYER_NOT_PRESENT` ([nixpkgs #216002](https://github.com/NixOS/nixpkgs/issues/216002)).
   A compositor that will not start is a bad failure mode from a greeter.
2. **This machine has a frame-generation Vulkan layer installed globally.**
   `/etc/vulkan/implicit_layer.d/VkLayer_LS_frame_generation.json` is an *implicit* layer with
   `disable_environment: DISABLE_LSFG=1` and **no `enable_environment` key** — meaning the
   Vulkan loader inserts it into every Vulkan instance by default, self-gating internally
   rather than being opt-in at the loader level. `vulkaninfo` confirms the loader advertises it
   (alongside `VK_LAYER_ALVR_capture`). Switching sway to Vulkan would pull a frame-generation
   layer and a VR capture layer into the compositor itself.

If this is attempted, scope both the renderer and `DISABLE_LSFG=1` to the sway launch in
`services.greetd.settings.default_session.command` rather than setting them globally — the same
class of mistake as the `GBM_BACKEND` leak already fixed.

*Recommendation: last resort, only if BPM is still poor after §2 and §4.3.*

### 4.6 Inherent, not fixable by configuration

Steam has no native Wayland backend; it runs on XWayland with `-use_xcomposite_workaround`,
which redirects its windows through an offscreen XComposite buffer, adding a copy per frame.
The flag is applied automatically on modern Linux and is not documented by Valve. Sluggish,
delayed UI interaction on Wayland is a tracked, open complaint
([#8744](https://github.com/ValveSoftware/steam-for-linux/issues/8744),
[#8852](https://github.com/ValveSoftware/steam-for-linux/issues/8852)). No 2026 announcement of
a native Wayland Steam client was found. Gamescope (§4.3) is the only real way around it.

---

## Key Takeaways

1. Skip the internet's default fix. `-cef-force-glx` / `-cef-disable-gpu` address a
   software-rendering fallback that is provably not occurring here — a live 6.2 MB
   `GrShaderCache` settles it.
2. The real local defect was compositor-side: forced software cursors disabled wlroots direct
   scan-out globally, which is precisely what fullscreen Big Picture depends on. Fixed.
3. Verify the cursor after the next login. That is the only regression risk from the change,
   and the sources genuinely disagree about whether NVIDIA hardware cursors are reliable yet.
4. `programs.gamescope.enableWsi = true` is now set; reach for the gamescope session (F3 at
   the greeter) if BPM is still poor on the desktop compositor — multiple reports show BPM
   performing correctly there when it is broken under a normal compositor.
5. Leave `capSysNice` off, and treat `WLR_RENDERER=vulkan` as a last resort — on this machine
   it would drag a global frame-generation layer into the compositor.

---

## Sources

1. [Steam issue #12694 — BPM lag, `-cef-force-glx` fix](https://github.com/ValveSoftware/steam-for-linux/issues/12694) — CEF EGL init failure → software rendering; the canonical fix that does not apply here.
2. [Steam issue #11255 — BPM lag/corruption on NVIDIA, works under gamescope](https://github.com/ValveSoftware/steam-for-linux/issues/11255) — also the Wayland "enable GPU accel web views" finding.
3. [Steam issue #9263 — Valve's BPM NVIDIA fix, no change](https://github.com/ValveSoftware/steam-for-linux/issues/9263)
4. [Steam issue #8744 — Steam UI not responsive on Wayland](https://github.com/ValveSoftware/steam-for-linux/issues/8744)
5. [Steam issue #8852 — Steam seems slow on Wayland](https://github.com/ValveSoftware/steam-for-linux/issues/8852)
6. [Steam issue #6630 — Steam library constantly consuming CPU on animation](https://github.com/ValveSoftware/steam-for-linux/issues/6630)
7. [Steam issue #10561 — UI black unless `-cef-disable-gpu`](https://github.com/ValveSoftware/steam-for-linux/issues/10561)
8. [CachyOS #1376 — Steam black screen on Niri, `-cef-disable-gpu`](https://github.com/CachyOS/CachyOS-PKGBUILDS/issues/1376)
9. [gamescope issue #521 — CAP_SYS_NICE breaks gamescope on NVIDIA](https://github.com/ValveSoftware/gamescope/issues/521)
10. [gamescope issue #1356 — nested gamescope breaks fullscreen child windows](https://github.com/ValveSoftware/gamescope/issues/1356)
11. [nixpkgs issue #216002 — sway won't start with WLR_RENDERER=vulkan on NVIDIA](https://github.com/NixOS/nixpkgs/issues/216002)
12. [NVIDIA developer forums — hardware cursor on Wayland/DRM](https://forums.developer.nvidia.com/t/hardware-cursor-is-not-working-on-wayland-drm-sessions/261853) — system-memory cursor buffer explanation.
13. [stephan-raabe/dotfiles #327 — NVIDIA hw cursor fixed from Hyprland 0.4x](https://gitlab.com/stephan-raabe/dotfiles/-/issues/327)
14. [justaguylinux/sway-setup — NVIDIA wiki](https://codeberg.org/justaguylinux/sway-setup/wiki/NVIDIA) — still recommends the variable.
15. [crispyricepc/sway-nvidia — wlroots-env-nvidia.sh](https://github.com/crispyricepc/sway-nvidia/blob/main/wlroots-env-nvidia.sh)
16. [Phoronix — Sway 1.7-rc1 zero-copy direct scanout](https://www.phoronix.com/news/Sway-1.7-rc1)
17. [Arch BBS #270454 — direct scan-out halving FPS on sway/NVIDIA](https://bbs.archlinux.org/viewtopic.php?id=270454)
18. [ArchWiki — Gamescope](https://wiki.archlinux.org/title/Gamescope)
19. [NixOS Wiki — Steam](https://wiki.nixos.org/wiki/Steam) — gamescopeSession, capSysNice, enableWsi.
20. [9to5Linux — Steam client update improves NVIDIA hardware acceleration on Linux](https://9to5linux.com/new-steam-client-update-improves-nvidia-gpu-hardware-acceleration-on-linux)
21. [GamingOnLinux — Valve tries to improve Big Picture Mode on Linux for NVIDIA](https://www.gamingonlinux.com/2023/05/valve-tries-to-improve-big-picture-mode-on-linux-for-nvidia-gpus/)
22. [Botmonster — gamescope HDR/VRR/FPS caps, gamescope-wsi on NVIDIA](https://botmonster.com/self-hosting/gamescope-desktop-linux-hdr-vrr-fps-limiting-steam/)

## Methodology

10 search queries across two engine sets (built-in WebSearch; open-websearch MCP over
DuckDuckGo and Brave for cross-checking), 7 sources deep-read via WebFetch. Every claim about
this machine was verified locally against running processes, `nvidia-smi`, Steam's own logs and
caches, the wlroots 0.20.2 source, and `nix eval` of the flake — not inferred from the sources.

Sub-questions investigated:
1. Why is the Steam desktop UI (Panorama/CEF) slow on Linux, and what are the known fixes?
2. What is specifically different about Big Picture Mode's performance profile?
3. What do Wayland/XWayland and NVIDIA contribute, and what is compositor-side?
4. What NixOS-specific options (`programs.steam`, `programs.gamescope`) are relevant?
5. Which of the above actually apply to this machine's measured state?

### Gaps and unverified items

- No before/after frame-rate measurement of Big Picture was taken; BPM was not opened during
  either session. The direct-scan-out mechanism is confirmed in source, the *magnitude* of its
  effect here is not measured.
- Whether NVIDIA hardware cursors work on driver 610 + wlroots 0.20.2 could not be determined
  from sources (they conflict) and cannot be tested without a re-login.
- Whether Chromium occlusion detection fails for Steam's stacked windows under XWayland (§4.2)
  is inferred from CPU sampling, not proven.
- `gamescope --backend wayland` behavior nested under sway on NVIDIA is reported broken for
  embedded Steam but was not tested here.
