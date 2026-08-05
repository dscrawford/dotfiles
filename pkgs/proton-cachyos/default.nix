# pkgs/proton-cachyos/default.nix
# CachyOS Proton pinned to 20260520: the 20260521 build crash-loops on NVIDIA
# 610.43.02. For `programs.steam.extraCompatPackages` only — it exposes a
# `steamcompattool` output and refuses to install into a normal environment.
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
  # These binaries run inside the Steam Linux Runtime; patching them breaks that.
  dontFixup = true;

  outputs = [
    "out"
    "steamcompattool"
  ];

  # $out is a refusal message, so this can't land in an environment by accident.
  # The cp source is the tarball's single top-level dir, which unpackPhase cd'd
  # into. Comments stay out of the phase body: it is a derivation input, and
  # editing one re-copies the whole multi-GB unpacked release.
  installPhase = ''
    runHook preInstall

    echo "${finalAttrs.pname} should not be installed into environments. Please use programs.steam.extraCompatPackages instead." > $out

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
