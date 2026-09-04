# node3 CDI: the EGL external platforms are missing from GPU containers

**Status: deployed 2026-09-04.** The mounts work as intended — Xwayland's
glamor now initialises on the card through GBM inside a GPU pod. Note the
result for the QA runner though: on this node's 580-branch driver that
glamor offers X11 clients *no GLX visual at all*, so an emulator drawing
through GLX gets no context. The QA image therefore pins `Xwayland -glamor
off` (see GOTG `docs/qa-platform-plan.md`); the compositor still runs on the
GPU. The mount is still right — anything using NVIDIA EGL directly, Wayland
platform included, now has a complete driver.

## Symptom

A container that asks for `nvidia.com/gpu-0` gets the card for anything that
uses `libEGL_nvidia` directly, and software rendering for anything that goes
through Xwayland. The GOTG QA runner (`gotg qa`, see
`~/Documents/GOTG/docs/qa-platform-plan.md`) shows it cleanly: the `cage`
compositor reports

```
EGL vendor: NVIDIA
GL renderer: NVIDIA GeForce GTX 1080 Ti/PCIe/SSE2
```

while the emulator it is compositing reports `Mesa 26.1.5` (llvmpipe), after

```
xwayland glamor: failed to setup GBM backend, falling back to sw accel
```

So GPU jobs run, and pass, while quietly grading a software renderer.

## Cause

`/run/opengl-driver/lib` is a symlink farm into the host nix store.
`hardware.nvidia-container-toolkit` mounts the driver package into the
container but not the EGL external-platform packages, so those symlinks
dangle — the file is listed, and `dlopen` fails:

| library | resolves to | in the container |
|---|---|---|
| `libEGL_nvidia.so.0` | `nvidia-x11-580.142` | present |
| `libGLX_nvidia.so.0` | `nvidia-x11-580.142` | present |
| `libnvidia-egl-gbm.so.1` | `nvidia-egl-external-platforms` → `egl-gbm` | **dangling** |
| `libnvidia-egl-xlib.so.1` | `nvidia-egl-external-platforms` → `egl-x11` | **dangling** |

Xwayland's glamor reaches the card through GBM, which needs
`libnvidia-egl-gbm`. It cannot load it, so it falls back to software and every
X11 client on that display falls back with it.

Note the chain is two deep: `/run/opengl-driver/lib/libnvidia-egl-gbm.so.1` →
`…-nvidia-egl-external-platforms/lib/…` → `…-egl-gbm-1.1.3/lib/…`. Mounting
only the first is not enough, which is why a hand-rolled hostPath mount of one
path did nothing.

## Verified

With the two store paths bind-mounted into a pod by hand, a ctypes probe on
node3 gets the whole way:

```
gbm_create_device -> ok   backend: nvidia
eglGetPlatformDisplay -> ok
eglInitialize -> 1 (EGL_SUCCESS), EGL 1.5
```

## Fix

The chain has one more hop than the table above shows. `/run/opengl-driver/lib`
does not link straight to `egl-gbm`; it links into the NixOS nvidia module's
`nvidia-egl-external-platforms` symlinkJoin, whose *relative* links then reach
`egl-gbm`, `egl-x11`, `egl-wayland`, `egl-wayland2`:

```
/run/opengl-driver/lib/libnvidia-egl-gbm.so.1
  -> …-nvidia-egl-external-platforms/lib/libnvidia-egl-gbm.so.1   (hop 1)
  -> libnvidia-egl-gbm.so.1.1.3                                    (relative)
  -> …-egl-gbm-1.1.3/lib/libnvidia-egl-gbm.so.1.1.3                (hop 2)
```

The toolkit's default profile mounts only `/run/opengl-driver`, the driver
package, and glibc (nixpkgs `nvidia-container-toolkit/default.nix`, the
`mounts` default), so both hops dangle. Mounting just `egl-gbm`/`egl-x11` leaves
hop 1 broken. The symlinkJoin is built inline by the nvidia module and has no
package attribute, so it is picked out of `hardware.graphics.extraPackages` by
name. All four ICD targets are mounted while at it — Wayland-native clients hit
the same wall through `libnvidia-egl-wayland`.

Applied to `hosts/node3/nvidia.nix`:

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

Rendered for node3 (`nix eval … hardware.nvidia-container-toolkit.mounts`),
the five entries land ahead of the module defaults, and the `egl-gbm` /
`egl-x11` paths are byte-identical to the symlinkJoin's targets — same
`pkgs`, so they cannot drift apart.

`containerPath` matches `hostPath` on purpose: the symlinks in
`/run/opengl-driver` are absolute store paths, so they only resolve if the
store path exists at the same place inside the container.

`egl-gbm` covers Xwayland; `egl-x11` covers EGL-on-X11 clients — needed
too, or pinning `__EGL_VENDOR_LIBRARY_FILENAMES` to NVIDIA (which the GBM
path also wants, or glvnd hands the GBM display to mesa and mesa rejects an
NVIDIA gbm device) breaks ares instead. The symlinkJoin mount also carries
`share/egl/egl_external_platform.d/*.json`, which is how libEGL_nvidia
discovers the platforms in the first place.

## After applying

```bash
# on node3, after the rebuild: the CDI spec is regenerated at /var/run/cdi
sudo nixos-rebuild switch --flake ~/.local/dotfiles#node3
```

Then re-run a GPU-tier QA job and confirm the emulator's own renderer line:

```bash
sed -e 's/@NAME@/gpu-check/' -e 's/@GAME@/usa.diddy_kong_racing_rev1/' \
  ~/Documents/GOTG/k8s/qa/job.yaml | kubectl apply -f -
```

It is fixed when the run's `session.log` reports an NVIDIA `OpenGL Version`
for the emulator rather than `Mesa … llvmpipe`, and no
`failed to setup GBM backend` line.
