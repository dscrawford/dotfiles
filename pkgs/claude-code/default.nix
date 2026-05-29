{ lib, stdenv, fetchurl, glibc, bubblewrap, procps, socat, makeWrapper, patchelf }:

let
  # Anthropic ships a per-platform prebuilt native binary as a separate npm
  # package: @anthropic-ai/claude-code-<suffix>. Map each Nix system to its
  # tarball suffix + hash.
  sources = {
    "x86_64-linux" = {
      suffix = "linux-x64";
      hash = "sha256-CPyCuWyJO6/ZJ2iEL3vidYUbtFXV0UnbH1PThNKM74A=";
    };
    "aarch64-linux" = {
      suffix = "linux-arm64";
      hash = "sha256-lwZe+vcqfuVT81k+OlmFfrmKO13v0WpaQJiORP4IIbc=";
    };
    "x86_64-darwin" = {
      suffix = "darwin-x64";
      hash = "sha256-etgvz0Rjx8iETPFLiSusQus14x34UegGhLc8c3pRcKA=";
    };
    "aarch64-darwin" = {
      suffix = "darwin-arm64";
      hash = "sha256-qDlfkYPbNxoPe4Ue4xVLY7jJNlnwpOaATs8j40+K7nM=";
    };
  };

  inherit (stdenv.hostPlatform) system;
  source =
    sources.${system}
      or (throw "claude-code: unsupported platform ${system}");
in
stdenv.mkDerivation rec {
  pname = "claude-code";
  version = "2.1.156";

  src = fetchurl {
    url = "https://registry.npmjs.org/@anthropic-ai/claude-code-${source.suffix}/-/claude-code-${source.suffix}-${version}.tgz";
    inherit (source) hash;
  };

  sourceRoot = "package";

  nativeBuildInputs =
    [ makeWrapper ]
    ++ lib.optionals stdenv.hostPlatform.isLinux [ patchelf ];

  dontBuild = true;
  dontConfigure = true;
  dontFixup = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 claude $out/lib/claude-code/claude
  ''
  # Linux binaries are glibc-linked ELF executables and must be patched to find
  # the Nix loader + libc. Darwin binaries are self-contained Mach-O and need no
  # patching.
  + lib.optionalString stdenv.hostPlatform.isLinux ''
    patchelf \
      --set-interpreter "$(cat ${stdenv.cc}/nix-support/dynamic-linker)" \
      --set-rpath "${lib.makeLibraryPath [ glibc ]}" \
      $out/lib/claude-code/claude
  ''
  + ''
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
    platforms = builtins.attrNames sources;
  };
}
