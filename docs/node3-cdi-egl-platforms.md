# node3 CDI: EGL external platforms missing from GPU containers

**Deployed 2026-09-04.** Xwayland's glamor now initialises on the card through GBM in
a GPU pod. But on node3's 580-branch driver that glamor offers X11 clients *no GLX
visual*, so a GLX emulator gets no context; the QA image pins `Xwayland -glamor off`
(GOTG `docs/qa-platform-plan.md`) and the compositor stays on the GPU. Anything using
NVIDIA EGL directly, Wayland included, now has a complete driver.

## Symptom

A container requesting `nvidia.com/gpu-0` got the card for `libEGL_nvidia` users and
software rendering through Xwayland. In `gotg qa`, `cage` reported

```
EGL vendor: NVIDIA
GL renderer: NVIDIA GeForce GTX 1080 Ti/PCIe/SSE2
```

while the emulator reported `Mesa 26.1.5` (llvmpipe) after

```
xwayland glamor: failed to setup GBM backend, falling back to sw accel
```

GPU jobs passed while grading a software renderer.

## Cause

`/run/opengl-driver/lib` is a symlink farm into the host store.
`hardware.nvidia-container-toolkit`'s default mounts are `/run/opengl-driver`, the
driver package and glibc (nixpkgs `nvidia-container-toolkit/default.nix`), so the EGL
platform links dangle:

| library | resolves to | in container |
|---|---|---|
| `libEGL_nvidia.so.0` | `nvidia-x11-580.142` | present |
| `libGLX_nvidia.so.0` | `nvidia-x11-580.142` | present |
| `libnvidia-egl-gbm.so.1` | `nvidia-egl-external-platforms` → `egl-gbm` | **dangling** |
| `libnvidia-egl-xlib.so.1` | `nvidia-egl-external-platforms` → `egl-x11` | **dangling** |

glamor needs `libnvidia-egl-gbm` for GBM; without it every X11 client on the display
falls back to software. The chain is two hops, through the nvidia module's inline
`nvidia-egl-external-platforms` symlinkJoin, so mounting only `egl-gbm` (or one
hand-rolled hostPath) does nothing:

```
/run/opengl-driver/lib/libnvidia-egl-gbm.so.1
  -> …-nvidia-egl-external-platforms/lib/libnvidia-egl-gbm.so.1   (hop 1)
  -> libnvidia-egl-gbm.so.1.1.3                                    (relative)
  -> …-egl-gbm-1.1.3/lib/libnvidia-egl-gbm.so.1.1.3                (hop 2)
```

With both store paths bind-mounted by hand, a ctypes probe on node3 got:

```
gbm_create_device -> ok   backend: nvidia
eglGetPlatformDisplay -> ok
eglInitialize -> 1 (EGL_SUCCESS), EGL 1.5
```

## Fix (`hosts/node3/nvidia.nix`)

```nix
hardware.nvidia-container-toolkit = {
  enable = true;
  mounts =
    let
      eglPlatforms = lib.findFirst
        (p: lib.hasPrefix "nvidia-egl-external-platforms" (lib.getName p))
        (throw "nvidia-egl-external-platforms not in hardware.graphics.extraPackages")
        config.hardware.graphics.extraPackages;
      same = path: { hostPath = path; containerPath = path; };
    in
    map same [
      "${eglPlatforms}"
      "${pkgs.egl-gbm}/lib"
      "${pkgs.egl-x11}/lib"
      "${pkgs.egl-wayland}/lib"
      "${pkgs.egl-wayland2}/lib"
    ];
};
```

- The symlinkJoin has no package attribute, so it's found in
  `hardware.graphics.extraPackages` by name. It also carries
  `share/egl/egl_external_platform.d/*.json`, which is how libEGL_nvidia finds the
  platforms.
- Same `pkgs`, so the `egl-gbm`/`egl-x11` paths are byte-identical to the
  symlinkJoin's targets.
- `containerPath = hostPath` because the links are absolute store paths.
- `egl-gbm` covers Xwayland; `egl-x11` covers EGL-on-X11. Both are needed: the GBM path
  wants `__EGL_VENDOR_LIBRARY_FILENAMES` pinned to NVIDIA (else glvnd hands the GBM
  display to mesa, which rejects it), and that pin breaks ares without `egl-x11`.
  Wayland clients need `egl-wayland`.

## Verify

```bash
sudo nixos-rebuild switch --flake "$HOME/.local/dotfiles?submodules=1#node3"   # regenerates /var/run/cdi
sed -e 's/@NAME@/gpu-check/' -e 's/@GAME@/usa.diddy_kong_racing_rev1/' \
  ~/Documents/GOTG/k8s/qa/job.yaml | kubectl apply -f -
```

Fixed when `session.log` shows an NVIDIA `OpenGL Version` for the emulator, not
`Mesa … llvmpipe`, and no `failed to setup GBM backend`.
