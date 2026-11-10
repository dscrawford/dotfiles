# Lossless Scaling (lsfg-vk) glitches in Helldivers 2 on Linux

*2026-08-25. 60+ sources. High confidence on the config finding (verified against the
installed source), medium on the artifact ranking.*

## Summary

**Lossless Scaling probably never runs on Helldivers 2**; the glitches are HD2's own
VKD3D/driver bugs. Launch options set `LSFG_PROCESS=helldivers2`, but the config block
is keyed `exe = "helldivers2.exe"`. In lsfg-vk **1.0.0** (installed) those don't match,
lookup falls back to the global config with `enable = false`, and the layer **silently
unloads**.

If it does engage, the next suspect is **mixed refresh rates** (165/165/60 Hz), which
the maintainer says break the vsync lsfg-vk relies on, in an HD2 thread from a reporter
on the same RTX 3080 Ti.

## 1. The config never matches (v1.0.0 source)

Installed: `/nix/store/lpnwmb3vm2hs0n6xa13dc1av0fm4v6jb-lsfg-vk-1.0.0` via
`pabloaul/lsfg-vk-flake`, so 1.x semantics apply, not 2.x `[[profile]]`/`LSFGVK_PROFILE`.

[`utils.cpp:211`](https://github.com/PancakeTAS/lsfg-vk/blob/v1.0.0/src/utils/utils.cpp):
`LSFG_PROCESS` sets both name fields verbatim.

```cpp
    const char* process_name = std::getenv("LSFG_PROCESS");
    if (process_name && *process_name != '\0')
        return { process_name, process_name };   // BOTH fields = "helldivers2"
```

[`config.cpp:153`](https://github.com/PancakeTAS/lsfg-vk/blob/v1.0.0/src/config/config.cpp):
match if the path **ends with** the key or comm **equals** it; else `globalConf`.

```cpp
auto it = std::ranges::find_if(games, [&name](const auto& pair) {
    return name.first.ends_with(pair.first) || (name.second == pair.first);
});
if (it != games.end())
    return it->second;

return globalConf;
```

`"helldivers2"` neither ends with nor equals `"helldivers2.exe"`, and no other block
(`vkcube`, `benchmark`, `Genshin`, `GameThread`) matches. The global config sets only
`.dll`, `.config_file`, `.timestamp` (`config.cpp:75`), so
[`config.hpp`](https://github.com/PancakeTAS/lsfg-vk/blob/v1.0.0/include/config/config.hpp)'s
`bool enable{false}` stands (game blocks set it, `config.cpp:98`). Then
[`main.cpp:42`](https://github.com/PancakeTAS/lsfg-vk/blob/v1.0.0/src/main.cpp):

```cpp
// exit silently if not enabled
auto& conf = Config::activeConf;
if (!conf.enable && name.second != "benchmark")
    return; // default configuration will unload
```

**Confirm:** when it engages it prints `lsfg-vk: Loaded configuration for <name>:` to
stderr (`main.cpp:47`). Grep the terminal or Proton log; absent means no frame gen.

**Fix:**

```
ENABLE_LSFG=1 LSFG_PROCESS=helldivers2.exe gamemoderun %command%
```

Dropping `LSFG_PROCESS` also works via the wine `.exe` scan
([#388](https://github.com/PancakeTAS/lsfg-vk/discussions/388), same game; its reporter
saw HD2 detected as `main`, a truncated render-thread comm). Explicit is more robust;
`LSFG_PROCESS` bypasses the 15-char comm limit.

## 2. Mixed refresh rates

| Output | Mode | Adaptive sync |
|---|---|---|
| DP-3 | 2560x1440 @ **164.958 Hz** | off |
| DP-2 | 3440x1440 @ **164.900 Hz** | off |
| DP-1 | 3840x2160 @ **59.997 Hz** | off |

[#364](https://github.com/PancakeTAS/lsfg-vk/discussions/364) (HD2, RTX 3080 Ti),
maintainer: "multiple monitors with mixed refresh rates … usually break vertical
synchronization and **lsfg-vk relies on this**." Unplugging the 60 Hz display fixed it.
lsfg-vk **forces FIFO** and leaves pacing to the compositor, since it can't know when
rendering finished ([Journey.md](https://github.com/PancakeTAS/lsfg-vk/blob/develop/docs/Journey.md)).
On DP-1, `multiplier = 2` at 60 fps gives 120 fps into 60 Hz, the worst case below.

## 3. If frame gen runs: glitch classes

**Generated FPS above refresh** (tearing, rainbow speckles, green pixels, black squares
on fast mouse camera turns). Bisected in
[decky #229](https://github.com/xXJSONDeruloXx/decky-lsfg-vk/issues/229): "disappears
completely if the total generated FPS is capped at or below the display's native
refresh rate"; also [decky #120](https://github.com/xXJSONDeruloXx/decky-lsfg-vk/issues/120),
[#113](https://github.com/xXJSONDeruloXx/decky-lsfg-vk/issues/113),
[#344](https://github.com/PancakeTAS/lsfg-vk/discussions/344),
[#397](https://github.com/PancakeTAS/lsfg-vk/discussions/397).

**HUD ghosting, unfixable:** lsfg-vk sees only the final image (no motion vectors,
depth or UI mask), and the maintainer closed
[#445](https://github.com/PancakeTAS/lsfg-vk/discussions/445) as out of scope. HD2 (static
crosshair over a fast third-person camera) is near worst case.

**HD2 post-processing fights flow estimation**
([PCGamingWiki](https://www.pcgamingwiki.com/wiki/Helldivers_2),
[HD2 wiki](https://helldivers.wiki.gg/wiki/User_Settings_Config_FPS_Optimization)):

| Feature | Problem |
|---|---|
| TAA (`taa_enabled`) | per-frame jitter reads as motion |
| Chromatic aberration (no toggle) | R/G/B move differently; `lens_quality_enabled = false` in `user_settings.config`, which the menu overwrites |
| DRS | internal res changes read as motion; `--disable-drs` |
| Particle overdraw | no coherent motion |
| SSR | reflections move unlike surfaces |

**Unstable base FPS:** HD2 is CPU-bound and drops in heavy fights. `DXVK_FRAME_RATE=<n>`
is a documented Linux-only fix for FPS "stuck at 30", evidence the in-game limiter
misbehaves under Proton.

## 4. HD2's own Linux bugs look the same

| Bug | Source |
|---|---|
| UI flicker with `PROTON_VKD3D_HEAP=1` | [vkd3d-proton #3040](https://github.com/HansKristian-Work/vkd3d-proton/issues/3040) |
| Black screen, UI visible (RTX 5080, 595.71.05) | [#3035](https://github.com/HansKristian-Work/vkd3d-proton/issues/3035) |
| Random artifacts each launch (amdgpu) | [#2223](https://github.com/HansKristian-Work/vkd3d-proton/issues/2223) |
| Deck texture corruption | [#2993](https://github.com/HansKristian-Work/vkd3d-proton/issues/2993) |
| HUD flicker / warped text after ~30 min | [Steam](https://steamcommunity.com/app/553850/discussions/1/4295943916781885280/) |
| Skybox dots with FSR or XeSS on | [Steam](https://steamcommunity.com/app/553850/discussions/1/657107714318754517/) |
| Fullscreen hangs; borderless stable | [Proton #7486](https://github.com/ValveSoftware/Proton/issues/7486) |

ProtonDB: Gold, 0.81, 2076 reports. HD2 is DX12 (Stingray), so it runs on VKD3D-Proton;
`--use-d3d11` switches to DXVK and changes present behaviour, a confound while debugging.

## 5. Ruled out

- **nProtect GameGuard:** no Linux evidence; lsfg-vk loads natively below VKD3D, outside
  the Wine PE module list (MangoHud uses the same path fine); GameGuard fails loudly.
- **`allow_fp16`:** "does not influence quality"; no-op on RTX 3000.
- **`gamemoderun`:** its NVIDIA path is unimplemented on Wayland
  ([#519](https://github.com/FeralInteractive/gamemode/issues/519)); fails as a no-op.
- **Driver 610.57.04:** fixes 595's `vkWaitForPresentKHR` busy-spin on Wayland
  ([forum](https://forums.developer.nvidia.com/t/nvidia-wayland-vulkan-wsi-busy-spins-in-vkwaitforpresentkhr-with-vk-khr-present-wait/367887));
  no 610 layer corruption reports.
- **Adaptive sync:** off everywhere, which is right; lsfg-vk doesn't support VRR.

**Hangs (not glitches):** lsfg-vk doesn't yet virtualise `VK_KHR_present_id{,2}` /
`present_wait{,2}` ([#464](https://github.com/PancakeTAS/lsfg-vk/issues/464)); NVIDIA
Smooth Motion deadlocked on the same hazard ([DXVK #5507](https://github.com/doitsujin/dxvk/issues/5507),
fixed in R595).

## Recommendations

1. `LSFG_PROCESS=helldivers2.exe`; confirm `lsfg-vk: Loaded configuration`.
2. Baseline without `ENABLE_LSFG`. If glitches persist, §4 is the problem.
3. Run on a 165 Hz output: 60 × 2 = 120 ≤ 165.
4. Disable DP-1 while testing.
5. In-game: borderless, V-Sync **on** (lsfg-vk Quirks; opposite of Windows guides), native
   render scale, upscaling and DRS off.
6. Cap externally: `DXVK_FRAME_RATE=60`.
7. Drop `PROTON_VKD3D_HEAP`; test `DISABLE_VK_LAYER_VALVE_steam_overlay_1=1` (overlay has a
   multi-`VkDevice` bug, [steam-for-linux #9120](https://github.com/ValveSoftware/steam-for-linux/issues/9120),
   and lsfg-vk creates a second device).
8. Accept HUD ghosting.

Gaps: no Linux image-quality evaluation of lsfg-vk on HD2 exists (artifact reports are
Windows-side); whether v1.0.0's fallback scans `/proc/self/maps` wasn't confirmed past
`utils.cpp:227`, hence the explicit `LSFG_PROCESS`.
