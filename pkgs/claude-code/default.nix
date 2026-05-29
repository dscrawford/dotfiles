{ lib, stdenv, fetchurl, glibc, bubblewrap, procps, socat, makeWrapper, patchelf }:

stdenv.mkDerivation rec {
  pname = "claude-code";
  version = "2.1.156";

  src = fetchurl {
    url = "https://registry.npmjs.org/@anthropic-ai/claude-code-linux-x64/-/claude-code-linux-x64-${version}.tgz";
    hash = "sha256-CPyCuWyJO6/ZJ2iEL3vidYUbtFXV0UnbH1PThNKM74A=";
  };

  sourceRoot = "package";

  nativeBuildInputs = [ makeWrapper patchelf ];

  dontBuild = true;
  dontConfigure = true;
  dontFixup = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 claude $out/lib/claude-code/claude

    patchelf \
      --set-interpreter "$(cat ${stdenv.cc}/nix-support/dynamic-linker)" \
      --set-rpath "${lib.makeLibraryPath [ glibc ]}" \
      $out/lib/claude-code/claude

    makeWrapper $out/lib/claude-code/claude $out/bin/claude \
      --set DISABLE_AUTOUPDATER 1 \
      --set-default FORCE_AUTOUPDATE_PLUGINS 1 \
      --set DISABLE_INSTALLATION_CHECKS 1 \
      --unset DEV \
      --prefix PATH : ${
        lib.makeBinPath (
          [ procps ]
          ++ lib.optionals stdenv.hostPlatform.isLinux [
            bubblewrap
            socat
          ]
        )
      }

    runHook postInstall
  '';

  meta = {
    description = "Agentic coding tool that lives in your terminal";
    homepage = "https://github.com/anthropics/claude-code";
    license = lib.licenses.unfree;
    mainProgram = "claude";
    platforms = [ "x86_64-linux" ];
  };
}
