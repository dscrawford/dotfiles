# --disable-gpu-rasterization: corrupted/garbled UI regions on NVIDIA+Wayland.
# settings.json's chromiumSwitches only accepts 13 Windows/macOS keys, so the
# commandLineArgs override is the only way to pass a flag. Electron 37 also
# negotiates dmabuf v3 while sway offers v5, so it never gets modifier feedback.
#
# LIBVA_DRIVER_NAME=none: nvidia-vaapi-driver 0.0.18 made Electron's VA-API
# decode usable, but stable Discord never calls vaSyncSurface, so streams
# stutter/freeze (elFarto/nvidia-vaapi-driver#455) and the renderer segfaults
# in libnvcuvid.so on driver 615. Canary 633720+ has Discord's fix; drop this
# once stable catches up.
{ pkgs }:

let
  discord = pkgs.discord.override { commandLineArgs = "--disable-gpu-rasterization"; };
in
pkgs.symlinkJoin {
  name = "discord-${discord.version}";
  paths = [ discord ];
  nativeBuildInputs = [ pkgs.makeWrapper ];
  postBuild = ''
    for bin in $out/bin/discord $out/bin/Discord; do
      wrapProgram "$bin" --set LIBVA_DRIVER_NAME none
    done
  '';
  inherit (discord) meta;
}
