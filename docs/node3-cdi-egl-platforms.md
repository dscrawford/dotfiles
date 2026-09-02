# node3 CDI: the EGL external platforms are missing from GPU containers

**Status: TODO.** Diagnosed and measured, not yet applied — the fix rebuilds
node3, which also runs Jellyfin, so it wants a moment when interrupting a
transcode is fine.

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

Add the external-platform packages to the CDI profile in
`hosts/node3/nvidia.nix`, so every GPU container sees a complete driver:

```nix
hardware.nvidia-container-toolkit = {
  enable = true;
  # /run/opengl-driver/lib symlinks into these, and without them the links
  # dangle inside a container: Xwayland's glamor cannot dlopen
  # libnvidia-egl-gbm, falls back to software, and takes every X11 client
  # on that display with it. The driver package alone is not enough.
  mounts = [
    {
      hostPath = "${pkgs.egl-gbm}/lib";
      containerPath = "${pkgs.egl-gbm}/lib";
    }
    {
      hostPath = "${pkgs.egl-x11}/lib";
      containerPath = "${pkgs.egl-x11}/lib";
    }
  ];
};
```

`containerPath` matches `hostPath` on purpose: the symlinks in
`/run/opengl-driver` are absolute store paths, so they only resolve if the
store path exists at the same place inside the container.

`egl-gbm` covers Xwayland; `egl-x11` covers EGL-on-X11 clients — needed
too, or pinning `__EGL_VENDOR_LIBRARY_FILENAMES` to NVIDIA (which the GBM
path also wants, or glvnd hands the GBM display to mesa and mesa rejects an
NVIDIA gbm device) breaks ares instead.

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
