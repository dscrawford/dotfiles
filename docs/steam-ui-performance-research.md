# Steam UI & Big Picture performance on NixOS/Wayland

*2026-08-04. 22 sources. Medium-high confidence.*

Machine: NixOS 26.11, sway 1.12 / wlroots 0.20.2, NVIDIA 610.43.02, RTX 3080 Ti, three
outputs (3840x2160@60, 3440x1440@165, 2560x1440@165), Steam build 1785799196.

## Summary

The internet's standard fix, `-cef-force-glx` or `-cef-disable-gpu`, **doesn't apply**:
Steam's CEF is already GPU-accelerated here. The real wins are compositor-side:
restoring wlroots direct scan-out (done, `hosts/local/local.nix`) and, if BPM is still
poor, the gamescope session with the WSI layer. Steam-side, only the Library
low-performance settings and fewer open CEF views help.

## 1. Ruled out

**CEF isn't in software fallback.** The usual failure is CEF's GPU process failing EGL
init on X11 and Steam silently rasterizing in software; the circulated fix is
`STEAM_RUNTIME=1 steam -no-cef-sandbox -cef-force-glx`
([#12694](https://github.com/ValveSoftware/steam-for-linux/issues/12694)). Here:

| Check | Result |
|---|---|
| `libGLX_nvidia.so.610.43.02` + `libnvidia-glcore` in every steamwebhelper | present |
| `nvidia-smi` VRAM | steamwebhelper 186 MiB + 404 MiB |
| `htmlcache/GrShaderCache` (written only when Skia rasterizes on GPU) | 6.2 MB, 95 files, mtime 2026-08-04 18:42 |

So `-cef-force-glx` is a no-op and `-cef-disable-gpu` a downgrade.
[#10561](https://github.com/ValveSoftware/steam-for-linux/issues/10561) and
[CachyOS #1376](https://github.com/CachyOS/CachyOS-PKGBUILDS/issues/1376) are black-screen
bugs, not slowness.

**Client is new enough.** The 2026-07-21 stable client fixed a steamwebhelper crash with
NVIDIA hardware acceleration ([9to5Linux](https://9to5linux.com/new-steam-client-update-improves-nvidia-gpu-hardware-acceleration-on-linux));
build 1785799196 (August) includes it. It fixed crashes, not UI speed.

**GPU selection is correct.** `GpuTopology` reports `default_gpu_id: 1`, the 3080 Ti
(llvmpipe is 2 and 3); `vulkaninfo` lists NVIDIA as GPU0.

## 2. Root cause: direct scan-out

`WLR_NO_HARDWARE_CURSORS=1` was set globally. wlroots 0.20.2
(`types/output/output.c:1002`):

```c
bool wlr_output_is_direct_scanout_allowed(struct wlr_output *output) {
	// If the output has at least one software cursor, reject direct scan-out
```

So every fullscreen surface, BPM above all, took a full render pass plus a copy each
frame, across 9840x2399 of desktop with two 165 Hz panels
([Sway 1.7 zero-copy scan-out](https://www.phoronix.com/news/Sway-1.7-rc1)).

**Risk: NVIDIA hardware cursors.** Sources conflict. NVIDIA explains the original
invisible cursor (wlroots put the cursor buffer in system memory)
([forums](https://forums.developer.nvidia.com/t/hardware-cursor-is-not-working-on-wayland-drm-sessions/261853)),
and sway-on-NVIDIA guides still set the variable
([sway-setup](https://codeberg.org/justaguylinux/sway-setup/wiki/NVIDIA)); Hyprland
0.4x users report it fixed and deprecated
([#327](https://gitlab.com/stephan-raabe/dotfiles/-/issues/327)). Test: log in and look at
the cursor; if it's invisible or corrupt, restore the line.

Old reports (driver 4xx) of scan-out halving FPS on sway/NVIDIA
([Arch #270454](https://bbs.archlinux.org/viewtopic.php?id=270454)): if things get
*worse*, `sway -Dnoscanout` isolates it.

## 3. Big Picture is compositor-bound

[#11255](https://github.com/ValveSoftware/steam-for-linux/issues/11255): massive BPM lag
on NVIDIA that "works correctly under Gamescope"; in the same thread, on Wayland,
*enabling* GPU-accelerated web views fixed BPM. Valve's repeated NVIDIA BPM fixes
haven't landed ([#9263](https://github.com/ValveSoftware/steam-for-linux/issues/9263)),
so route around it.

## 4. Options, ranked

1. **Steam settings (free).** Library → Low Performance Mode, Low Bandwidth Mode, small
   display size ([#6630](https://github.com/ValveSoftware/steam-for-linux/issues/6630)
   documents animation CPU burn). Keep GPU-accelerated web views **on**.
2. **Fewer CEF views (free, medium confidence).** Main, Friends and a chat window were
   stacked in one tabbed container; two renderers sampled 10.1% and 12.8% CPU in the
   background. Under XWayland with `-use_xcomposite_workaround`, Chromium's occlusion
   throttling may not fire (inferred). Close Friends and chat when idle.
3. **Gamescope for BPM.** `programs.steam.gamescopeSession` gives a greeter entry; NVIDIA
   needs `programs.gamescope.enableWsi = true` (now set in `hosts/local/steam.nix`) and
   modesetting (on) ([ArchWiki](https://wiki.archlinux.org/title/Gamescope)). Prefer the
   greeter session over nesting in sway
   ([gamescope #1356](https://github.com/ValveSoftware/gamescope/issues/1356)).
4. **Leave `capSysNice` off.** On NVIDIA it can cause `vkCreateDevice failed
   (VkResult: -3)` ([gamescope #521](https://github.com/ValveSoftware/gamescope/issues/521),
   open since 2022; untested on 610).
5. **`WLR_RENDERER=vulkan`, scoped to sway.** Sway has failed to start with it on NVIDIA
   (`ERROR_LAYER_NOT_PRESENT`, [nixpkgs #216002](https://github.com/NixOS/nixpkgs/issues/216002)),
   and the implicit `VkLayer_LS_frame_generation` layer (no `enable_environment`, gated by
   `DISABLE_LSFG=1`) plus `VK_LAYER_ALVR_capture` load into every Vulkan instance. Set it
   only on the greetd sway command, never globally. (Since adopted that way in
   `hosts/local/services.nix`.)

Inherent: Steam has no native Wayland backend; `-use_xcomposite_workaround` adds an
offscreen copy per frame ([#8744](https://github.com/ValveSoftware/steam-for-linux/issues/8744),
[#8852](https://github.com/ValveSoftware/steam-for-linux/issues/8852)). Only gamescope avoids it.

## Gaps

- No BPM frame-rate before/after; the scan-out mechanism is from source, its size here is
  unmeasured.
- NVIDIA hardware cursors on 610 + wlroots 0.20.2 need a re-login to test.
- The occlusion explanation in option 2 is inferred from CPU samples.
