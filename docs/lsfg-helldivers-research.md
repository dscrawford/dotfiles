# Lossless Scaling (lsfg-vk) glitches in Helldivers 2 on Linux

*Generated: 2026-08-25 | Sources: 60+ | Confidence: High on the config finding (verified against installed source), Medium on the artifact ranking*

## Executive summary

**The most likely answer is that Lossless Scaling is not running on Helldivers 2 at
all**, and the glitches you're seeing are Helldivers 2's own well-documented
VKD3D/driver rendering bugs on Linux.

Your Steam launch options set `LSFG_PROCESS=helldivers2`, but your config block is
keyed on `exe = "helldivers2.exe"`. In lsfg-vk **1.0.0** — the version installed
here — those do not match, the lookup falls back to the global config, and the
global config's `enable` flag is `false`, so the layer **silently unloads**. This
is traced end-to-end through the v1.0.0 source below, not inferred.

If it turns out the layer *is* engaging on your machine, the second-ranked cause is
your **mixed refresh rates** (165/165/60 Hz), which the lsfg-vk maintainer has
called out as breaking the vsync assumption the entire design rests on — in a
Helldivers 2 thread, from a reporter on the *same RTX 3080 Ti*.

Either way, there is a genuine root cause to fix, and it is not the interpolation
quality.

## 1. The config never matches — traced through the installed source

Installed build: `/nix/store/lpnwmb3vm2hs0n6xa13dc1av0fm4v6jb-lsfg-vk-1.0.0`, via
`pabloaul/lsfg-vk-flake` pinned in `flake.nix:21`. So **1.x semantics apply**, not
the 2.x `[[profile]]`/`LSFGVK_PROFILE` scheme now on `develop`.

**Step 1 — `LSFG_PROCESS` overrides both name fields.**
[`src/utils/utils.cpp@v1.0.0:211`](https://github.com/PancakeTAS/lsfg-vk/blob/v1.0.0/src/utils/utils.cpp):

```cpp
std::pair<std::string, std::string> Utils::getProcessName() {
    const char* process_name = std::getenv("LSFG_PROCESS");
    if (process_name && *process_name != '\0')
        return { process_name, process_name };   // BOTH fields = "helldivers2"
```

It does not append `.exe`, strip anything, or normalise.

**Step 2 — the matching predicate.**
[`src/config/config.cpp@v1.0.0:153`](https://github.com/PancakeTAS/lsfg-vk/blob/v1.0.0/src/config/config.cpp):

```cpp
auto it = std::ranges::find_if(games, [&name](const auto& pair) {
    return name.first.ends_with(pair.first) || (name.second == pair.first);
});
if (it != games.end())
    return it->second;

return globalConf;   // <-- no match falls through to GLOBAL
```

Match ⟺ path **ends_with** the config key, **or** comm **equals** it exactly.

**Step 3 — evaluate your case.** `name.first = name.second = "helldivers2"`;
your key is `"helldivers2.exe"`:

- `"helldivers2".ends_with("helldivers2.exe")` → **false** (needle longer than haystack)
- `"helldivers2" == "helldivers2.exe"` → **false**

None of your other blocks match either (`vkcube`, `benchmark`, `Genshin`,
`GameThread`). So it returns `globalConf`.

**Step 4 — the global config has `enable = false`.** The global `Configuration` is
built with designated initialisers naming only `.dll`, `.config_file`,
`.timestamp` (`config.cpp:75`), so every other member takes its in-class default —
and in [`include/config/config.hpp@v1.0.0`](https://github.com/PancakeTAS/lsfg-vk/blob/v1.0.0/include/config/config.hpp):

```cpp
bool enable{false};        // <-- never set to true for the global config
size_t multiplier{2};
```

Game blocks set `.enable = true` explicitly (`config.cpp:98`). The global one never does.

**Step 5 — the layer unloads.**
[`src/main.cpp@v1.0.0:42`](https://github.com/PancakeTAS/lsfg-vk/blob/v1.0.0/src/main.cpp):

```cpp
// exit silently if not enabled
auto& conf = Config::activeConf;
if (!conf.enable && name.second != "benchmark")
    return; // default configuration will unload
```

No frame generation, no swapchain interception, no present-mode override, **and no
error message**.

### How to confirm in ten seconds

When lsfg-vk *does* engage it prints to stderr (`main.cpp:47`):

```
lsfg-vk: Loaded configuration for <name>:
  Multiplier: 2
  Flow Scale: 0.8
  ...
```

Launch HD2 from a terminal, or check the Proton log, and grep for
`lsfg-vk: Loaded configuration`. **Absent ⇒ frame generation never ran** and every
glitch you've seen is something else.

### The fix

```
ENABLE_LSFG=1 LSFG_PROCESS=helldivers2.exe gamemoderun %command%
```

Adding `.exe` makes `name.second == "helldivers2.exe"` an exact match against your
existing config block. Dropping `LSFG_PROCESS` entirely also works — it falls back
to scanning for the wine `.exe`, which is what
[discussion #388](https://github.com/PancakeTAS/lsfg-vk/discussions/388) reports as
the fix for this exact game ("just change the profile name to `helldivers2.exe`").
Setting it explicitly is more robust since it doesn't depend on the maps-scan path.

**Corroborating field evidence:** #388's reporter found lsfg-vk detected HD2 as
**`main`** — the 15-char-truncated `/proc/self/comm` of a Proton render thread —
and generated nothing. Your config comment reasons about the 15-char `comm` limit,
which is correct, but `LSFG_PROCESS` bypasses `comm` entirely and makes the limit
irrelevant.

## 2. Mixed refresh rates — the #1 risk if the layer *is* running

Your outputs:

| Output | Mode | Adaptive sync |
|---|---|---|
| DP-3 | 2560x1440 @ **164.958 Hz** | disabled |
| DP-2 | 3440x1440 @ **164.900 Hz** | disabled |
| DP-1 | 3840x2160 @ **59.997 Hz** | disabled |

From [discussion #364](https://github.com/PancakeTAS/lsfg-vk/discussions/364) —
*a Helldivers 2 thread, reporter on an **RTX 3080 Ti**, same as yours* — the
maintainer:

> "Do you have multiple monitors with mixed refresh rates? Those usually break
> vertical synchronization and **lsfg-vk relies on this at the moment**."

Unplugging the 60 Hz display made it "work perfectly" for that reporter.

This matters structurally. Per [`docs/Journey.md`](https://github.com/PancakeTAS/lsfg-vk/blob/develop/docs/Journey.md),
lsfg-vk deliberately **forces FIFO** and delegates all pacing to the compositor,
because it cannot know when rendering finished (the app's `pWaitSemaphores` are
GPU-only). Its entire timing model is "the compositor will pace us." A compositor
juggling 165/165/60 Hz outputs does not provide the stable vblank cadence that
model assumes.

Note even DP-3 and DP-2 differ slightly (164.958 vs 164.900 Hz).

**Second-order risk:** if HD2 opens on **DP-1 (60 Hz)**, your `multiplier = 2` on a
60 fps base produces **120 generated fps into a 60 Hz output**. That is precisely
the best-evidenced artifact class in the whole corpus — see §3.

## 3. If frame gen *is* running: the documented glitch classes

### 3a. Generated FPS exceeding display refresh — the dominant, user-bisected cause

The single best-supported root cause, and it is a *pacing* failure, not an
interpolation-quality one. Symptoms: tearing, **rainbow speckles**, green pixels,
**black squares**, corruption blocks — all strongly correlated with fast camera
rotation via mouse.

User bisection in [decky #229](https://github.com/xXJSONDeruloXx/decky-lsfg-vk/issues/229):

> "When generated FPS > Display Hz (e.g. 71fps x2 on a 90Hz screen) using FIFO,
> camera rotation causes severe artifacts/stutter… **The issue disappears
> completely if the total generated FPS is capped at or below the display's native
> refresh rate.**"

Independently reproduced in [decky #120](https://github.com/xXJSONDeruloXx/decky-lsfg-vk/issues/120),
[decky #113](https://github.com/xXJSONDeruloXx/decky-lsfg-vk/issues/113),
[discussion #344](https://github.com/PancakeTAS/lsfg-vk/discussions/344),
[discussion #397](https://github.com/PancakeTAS/lsfg-vk/discussions/397).

*(Inference: the mouse correlation isn't about input devices — pointer input drives
high-velocity camera rotation, maximising optical-flow magnitude and saturating the
present queue. The morphology is characteristic of presenting an image still being
written.)*

### 3b. HUD/UI/text ghosting — architecturally unfixable

lsfg-vk consumes only the final composited swapchain image. **No motion vectors, no
depth buffer, no UI mask.** Static HUD elements sit atop high-magnitude background
flow, so the estimator drags them with the scene behind them.

Maintainer, closing [discussion #445](https://github.com/PancakeTAS/lsfg-vk/discussions/445)
("Hud fix for ghosting") as out of scope:

> "This is beyond the scope of the project. I simply port LSFG to linux,
> translating each shader one by one, I do not add any new functionality."

**Helldivers 2 is close to a worst case for this**: a static crosshair over a
fast-panning third-person camera, small HUD text, and a stratagem overlay. Windows
LSFG users report exactly this — "crosshair ghosting… artifacting around the edges
of screens and HUD elements", "looks like motion blur and looks really bad".

### 3c. HD2's post-processing actively fights image-space interpolation

All confirmed on [PCGamingWiki](https://www.pcgamingwiki.com/wiki/Helldivers_2) /
[the HD2 wiki](https://helldivers.wiki.gg/wiki/User_Settings_Config_FPS_Optimization):

| Feature | Why it breaks flow estimation |
|---|---|
| **TAA** (`taa_enabled`) | sub-pixel jitter every frame = motion that isn't motion |
| **Chromatic aberration, always on, no menu toggle** | per-channel radial displacement; R/G/B of the same object move differently. Only fix: `lens_quality_enabled = false` in `user_settings.config` — **and the in-game menu overwrites that file** |
| **Dynamic Resolution Scaling** | internal res changes mid-scene at fixed swapchain res → non-motion change read as motion. Disable via `--disable-drs` |
| **Particle overdraw** | semi-transparent layers with no coherent per-pixel motion vector |
| **SSR** | reflections move at a different rate than their surfaces |

### 3d. Unstable base framerate

HD2 is **CPU-bound**, and its base framerate collapses during exactly the heavy
particle/enemy moments where you want smoothness. A fixed 2× interpolator fed an
unstable base produces judder that reads as an interpolation defect.

The HD2 wiki documents `DXVK_FRAME_RATE=<n>` as a **Linux-only** override for FPS
"stuck at 30" — the existence of that workaround is itself evidence the in-game
limiter misbehaves under Proton. A separate report ("Inaccurate FPS in Linux")
describes HD2 counting 120 fps on Linux while *looking* like 60.

## 4. HD2's baseline Linux bugs — these look identical to frame-gen glitches

**This is why §1 matters so much.** Helldivers 2 has live, open rendering bugs on
Linux with zero frame-gen involvement, and several are swapchain/present-adjacent:

| Bug | Source |
|---|---|
| **UI flickering** with VKD3D descriptor heaps (`PROTON_VKD3D_HEAP=1`) | [vkd3d-proton #3040](https://github.com/HansKristian-Work/vkd3d-proton/issues/3040) — open |
| **Black screen with UI still visible** — RTX 5080, driver 595.71.05 | [vkd3d-proton #3035](https://github.com/HansKristian-Work/vkd3d-proton/issues/3035) |
| **Extreme random visual artifacts, different every launch** | [vkd3d-proton #2223](https://github.com/HansKristian-Work/vkd3d-proton/issues/2223) — amdgpu VRAM-clear regression |
| Texture corruption on Deck | [vkd3d-proton #2993](https://github.com/HansKristian-Work/vkd3d-proton/issues/2993) |
| Flickering HUD, missing letters, warped text after ~30 min | [Steam, GTX 10-series](https://steamcommunity.com/app/553850/discussions/1/4295943916781885280/) |
| Skybox corruption (multicoloured flashing dots) **when upscaling is enabled** | [Steam](https://steamcommunity.com/app/553850/discussions/1/657107714318754517/) — FSR *and* XeSS |
| Fullscreen hangs; borderless is the stable mode | PCGamingWiki; [Proton #7486](https://github.com/ValveSoftware/Proton/issues/7486) |

ProtonDB rates HD2 **Gold, 0.81, 2076 reports** — tweaks expected, not flawless.

**Also note:** HD2 is **DirectX 12** on the Autodesk Stingray engine, so Proton
routes it through **VKD3D-Proton, not DXVK**. The `--use-d3d11` launch flag switches
to DXVK, which changes swapchain creation and present behaviour entirely — a real
confound if you toggle it while debugging.

## 5. Ruled out or deprioritised

- **nProtect GameGuard.** No evidence at all on Linux. Architecturally implausible:
  lsfg-vk is a native `.so` loaded by the host Vulkan loader *below* VKD3D and
  outside the Wine prefix; GameGuard is PE code enumerating Wine's PE module list.
  MangoHud (same injection mechanism) is used routinely by HD2 Linux players with
  no complaints. GameGuard failures are also loud — error codes, an nProtect FAQ
  page opening itself. **Do not chase this.**
- **`allow_fp16 = true`.** Documented as *"This option does not influence quality"* —
  performance-only, and a no-op on RTX 3000. Not a suspect.
- **`gamemoderun`.** Its NVIDIA GPU path is unimplemented on Wayland
  ([GameMode #519](https://github.com/FeralInteractive/gamemode/issues/519)), so it's
  effectively CPU-governor only. Documented failure mode is "does nothing", not
  "corrupts". Could affect pacing; implausible as a corruption source.
- **Driver 610.57.04.** Counter to the assumption in `bar1-crash-research.md` Tier 2,
  610.x is *better* than 595.x here: it **fixes** the `vkWaitForPresentKHR`
  Wayland busy-spin present in 595.58.03/595.71.05
  ([NVIDIA forums](https://forums.developer.nvidia.com/t/nvidia-wayland-vulkan-wsi-busy-spins-in-vkwaitforpresentkhr-with-vk-khr-present-wait/367887)),
  and fixes a 595 regression causing black screens. No 610.x-specific layer or DXVK
  corruption reports found.
- **Adaptive sync.** Already `off` on all three outputs in `~/.config/sway/outputs`
  — good, since lsfg-vk does not support VRR and VRR flicker is reported on both
  595.x and 610.x.

## 6. Worth knowing: `present_id` / `present_wait`

lsfg-vk [issue #464](https://github.com/PancakeTAS/lsfg-vk/issues/464) ("virtual
swapchain") documents that the layer does **not yet** virtualise
`VK_KHR_present_id{,2}` / `VK_KHR_present_wait{,2}` — necessary because once the
layer presents extra frames, the app's present IDs no longer map 1:1 to real
presents.

There is a direct precedent for this going wrong on NVIDIA:
[DXVK #5507](https://github.com/doitsujin/dxvk/issues/5507) — NVIDIA Smooth Motion
frame generation deadlocked HoYo games via `present_id2`/`present_wait2`, fixed
driver-side in R595 beta ("Fixed hang when NVIDIA Smooth Motion is enabled in
applications that use `VK_KHR_present_id2`"). Different frame-gen implementation,
same structural hazard. If you hit hard *hangs* rather than visual glitches, this
is where to look.

## Recommendations, ranked

1. **Fix the process match** — `LSFG_PROCESS=helldivers2.exe` in the launch options.
   Then verify with `lsfg-vk: Loaded configuration` on stderr. Until you see that
   line, you are not testing frame generation at all.
2. **Establish a clean baseline first.** Run HD2 with `ENABLE_LSFG` removed
   entirely and see whether the glitches persist. Given §1, expect that they do —
   in which case §4 is your actual problem and frame gen is a red herring.
3. **Put the game on a 165 Hz output and keep 60 fps × 2 = 120 ≤ 165.** If it lands
   on DP-1 (60 Hz), 120 into 60 Hz is the documented worst case.
4. **Consider unplugging/disabling DP-1 while testing** — mixed refresh is the
   documented HD2 + lsfg-vk killer on your exact GPU.
5. **In-game: borderless window, V-Sync on, render scale native, upscaling off,
   DRS off.** Note lsfg-vk's Quirks page says V-Sync **on** and don't override the
   present mode — this *contradicts* every Windows LSFG guide, which says off.
   On Linux follow lsfg-vk.
6. **Cap externally**, not in-game: `DXVK_FRAME_RATE=60`. HD2's own limiter is
   documented as unreliable under Proton.
7. **Kill confounds:** drop `PROTON_VKD3D_HEAP` if set (#3040/#3035 are UI-flicker
   and black-screen bugs triggered by heap args), and test
   `DISABLE_VK_LAYER_VALVE_steam_overlay_1=1` — the Steam overlay has an open
   multi-`VkDevice` bug ([steam-for-linux #9120](https://github.com/ValveSoftware/steam-for-linux/issues/9120))
   and lsfg-vk deliberately creates a second `VkDevice`.
8. **Accept HUD ghosting as permanent** if you do get it running. It is
   maintainer-confirmed out of scope and unfixable without a UI mask.

## Key takeaways

1. `LSFG_PROCESS=helldivers2` ≠ `exe = "helldivers2.exe"`. Verified through v1.0.0
   source: no match → global config → `enable=false` → silent unload. **Frame
   generation has probably never run on your HD2.**
2. It fails **silently** — no warning, no error. Check for
   `lsfg-vk: Loaded configuration` before concluding anything.
3. HD2 has open VKD3D bugs producing UI flicker, black-screen-with-visible-UI, and
   "extreme random visual artifacts" — all easily misread as frame-gen glitches.
4. Your 165/165/60 Hz setup is the documented lsfg-vk breaker, called out by the
   maintainer in an HD2 thread from an RTX 3080 Ti reporter.
5. HUD/crosshair ghosting is architectural and permanent — no motion vectors, no UI
   mask, out of scope upstream.
6. GameGuard is not your problem. Neither is `allow_fp16`, `gamemoderun`, or the
   610 driver.

## Sources

**Source-verified (installed build, v1.0.0):**
[config.cpp](https://github.com/PancakeTAS/lsfg-vk/blob/v1.0.0/src/config/config.cpp) ·
[utils.cpp](https://github.com/PancakeTAS/lsfg-vk/blob/v1.0.0/src/utils/utils.cpp) ·
[config.hpp](https://github.com/PancakeTAS/lsfg-vk/blob/v1.0.0/include/config/config.hpp) ·
[main.cpp](https://github.com/PancakeTAS/lsfg-vk/blob/v1.0.0/src/main.cpp)

**lsfg-vk:** [Journey.md](https://github.com/PancakeTAS/lsfg-vk/blob/develop/docs/Journey.md) ·
[Troubleshooting.md](https://github.com/PancakeTAS/lsfg-vk/blob/develop/docs/Troubleshooting.md) ·
[Wiki: Quirks](https://github.com/PancakeTAS/lsfg-vk/wiki/Quirks) ·
[#464](https://github.com/PancakeTAS/lsfg-vk/issues/464) ·
[#231](https://github.com/PancakeTAS/lsfg-vk/issues/231) ·
[#234](https://github.com/PancakeTAS/lsfg-vk/issues/234) ·
[#122](https://github.com/PancakeTAS/lsfg-vk/issues/122) ·
[#61](https://github.com/PancakeTAS/lsfg-vk/issues/61) ·
[#244](https://github.com/PancakeTAS/lsfg-vk/issues/244) ·
discussions [#364](https://github.com/PancakeTAS/lsfg-vk/discussions/364) (HD2, RTX 3080 Ti) ·
[#388](https://github.com/PancakeTAS/lsfg-vk/discussions/388) (HD2, name fix) ·
[#445](https://github.com/PancakeTAS/lsfg-vk/discussions/445) (HUD ghosting, out of scope) ·
[#344](https://github.com/PancakeTAS/lsfg-vk/discussions/344) ·
[#397](https://github.com/PancakeTAS/lsfg-vk/discussions/397) ·
[#531](https://github.com/PancakeTAS/lsfg-vk/discussions/531) (Fossilize kills the hook)

**decky-lsfg-vk:** [#229](https://github.com/xXJSONDeruloXx/decky-lsfg-vk/issues/229) (bisection) ·
[#120](https://github.com/xXJSONDeruloXx/decky-lsfg-vk/issues/120) ·
[#113](https://github.com/xXJSONDeruloXx/decky-lsfg-vk/issues/113) ·
[#121](https://github.com/xXJSONDeruloXx/decky-lsfg-vk/issues/121) ·
[#163](https://github.com/xXJSONDeruloXx/decky-lsfg-vk/issues/163)

**Helldivers 2:** [PCGamingWiki](https://www.pcgamingwiki.com/wiki/Helldivers_2) ·
[Linux troubleshooting](https://helldivers.wiki.gg/wiki/Linux_/_Steam_Deck_Troubleshooting) ·
[Launch commands](https://helldivers.wiki.gg/wiki/Steam_Launch_Commands) ·
[FPS optimization](https://helldivers.wiki.gg/wiki/User_Settings_Config_FPS_Optimization) ·
[ProtonDB summary](https://www.protondb.com/api/v1/reports/summaries/553850.json) ·
[Proton #7486](https://github.com/ValveSoftware/Proton/issues/7486) ·
vkd3d-proton [#3040](https://github.com/HansKristian-Work/vkd3d-proton/issues/3040)
[#3035](https://github.com/HansKristian-Work/vkd3d-proton/issues/3035)
[#2993](https://github.com/HansKristian-Work/vkd3d-proton/issues/2993)
[#2223](https://github.com/HansKristian-Work/vkd3d-proton/issues/2223)
[#2934](https://github.com/HansKristian-Work/vkd3d-proton/issues/2934) ·
[PC Gamer on the Stingray engine](https://www.pcgamer.com/helldivers-2-engine-bitsquid-autodesk-stingray/)

**Stack:** [DXVK #5507](https://github.com/doitsujin/dxvk/issues/5507) ·
[DXVK #5330](https://github.com/doitsujin/dxvk/issues/5330) ·
[Vulkan-Loader #328](https://github.com/KhronosGroup/Vulkan-Loader/issues/328) (implicit layer order, open) ·
[steam-for-linux #9120](https://github.com/ValveSoftware/steam-for-linux/issues/9120) ·
[NVIDIA present_wait busy-spin](https://forums.developer.nvidia.com/t/nvidia-wayland-vulkan-wsi-busy-spins-in-vkwaitforpresentkhr-with-vk-khr-present-wait/367887) ·
[610 feedback thread](https://forums.developer.nvidia.com/t/610-release-feedback-discussion/371356) ·
[610.57.04 wayland-issues](https://download.nvidia.com/XFree86/Linux-x86_64/610.57.04/README/wayland-issues.html) ·
[GameMode #519](https://github.com/FeralInteractive/gamemode/issues/519) ·
[PCGamingWiki: GameGuard](https://www.pcgamingwiki.com/wiki/NProtect_GameGuard)

## Methodology

Three parallel research agents across ~60 sources (lsfg-vk repo/issues/discussions,
vkd3d-proton, DXVK, Proton, Vulkan-Loader, NVIDIA developer forums, ProtonDB API,
PCGamingWiki, Steam discussions), then **direct verification against the installed
build**: nix store path and version, `~/.config/lsfg-vk/conf.toml`, Steam launch
options, sway output modes and adaptive-sync state, and the v1.0.0 source of
`config.cpp` / `utils.cpp` / `config.hpp` / `main.cpp` fetched via the GitHub API.

**Correction made during verification:** an agent reported that a non-matching
config causes `Config::currentConf.reset()` and an explicit "disabling" message.
That is a *different commit*. At the v1.0.0 tag your binary was built from, the
lookup returns `globalConf`, whose `enable` defaults to `false`, and `main.cpp`
returns silently. Same outcome — no frame generation — via a different and quieter
path.

**Gaps:** no published Linux-side image-quality evaluation of lsfg-vk on HD2 exists;
every Linux HD2 report found is about it not launching or not engaging, and the
artifact corpus is entirely Windows-side. Two Steam Deck LSFG-VK YouTube videos
were not transcribable. Whether v1.0.0's fallback path scans `/proc/self/maps` for
the wine `.exe` was not confirmed past line 227 of `utils.cpp` — which is why the
recommended fix sets `LSFG_PROCESS=helldivers2.exe` explicitly rather than relying
on that path.
