# pkgs/proton-cachyos/default.nix
# CachyOS Proton, pinned to a specific dated build.
#
# Pinned to the 20260520 (x86_64_v3) release because the 20260521 build is
# known-broken with NVIDIA driver 610.43.02 (illegal-instruction / vkd3d crash
# loop). See Forza Horizon 6 (app 2483190) troubleshooting.
#
# Intended for use with `programs.steam.extraCompatPackages` ONLY — it exposes a
# `steamcompattool` output and refuses to be added to a normal environment.
# The binaries are unpatched and run inside the Steam Linux Runtime container,
# so no patchelf/strip fixup is applied.
{
  lib,
  stdenvNoCC,
  fetchurl,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "proton-cachyos-bin";
  version = "11.0-20260520-slr";

  src = fetchurl {
    url = "https://github.com/CachyOS/proton-cachyos/releases/download/cachyos-${finalAttrs.version}/proton-cachyos-${finalAttrs.version}-x86_64_v3.tar.xz";
    hash = "sha256-YSDaUcoYYfT/UMkxpULfq7fVvELAhi8b/wIrpSv4yJQ=";
  };

  dontConfigure = true;
  dontBuild = true;
  # Proton ships prebuilt Wine/DXVK/vkd3d binaries meant to run inside the
  # Steam Linux Runtime (pressure-vessel) sandbox. Patching them breaks that.
  dontFixup = true;

  outputs = [
    "out"
    "steamcompattool"
  ];

  installPhase = ''
    runHook preInstall

    # Block accidental inclusion in a user/system environment.
    echo "${finalAttrs.pname} should not be installed into environments. Please use programs.steam.extraCompatPackages instead." > $out

    # The tarball unpacks to a single top-level dir; unpackPhase cd's us into it.
    mkdir -p "$steamcompattool"
    cp -a . "$steamcompattool/"

    runHook postInstall
  '';

  meta = {
    description = "CachyOS Proton (pinned 20260520, x86_64_v3) Steam Play compatibility tool";
    homepage = "https://github.com/CachyOS/proton-cachyos";
    license = lib.licenses.bsd3;
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
})
