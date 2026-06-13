{ lib, stdenv, fetchurl, glibc, bubblewrap, procps, socat, makeWrapper, patchelf }:

let
  # Anthropic ships a per-platform prebuilt native binary as a separate npm
  # package: @anthropic-ai/claude-code-<suffix>. Map each Nix system to its
  # tarball suffix + hash.
  sources = {
    "x86_64-linux" = {
      suffix = "linux-x64";
      hash = "sha256-WgnUx2ErN0L9rrGmQUh5jGqnldv9dYcQnTva15zNU/8=";
    };
    "aarch64-linux" = {
      suffix = "linux-arm64";
      hash = "sha256-np1UdJEhAz6o/1mJNPYVfqjmUWjK+/nN7IVjb4g5wU4=";
    };
    "x86_64-darwin" = {
      suffix = "darwin-x64";
      hash = "sha256-8+YyVRc9w6n8qky+lFuHRUyFMOXSRa/81bIHsgw+i7A=";
    };
    "aarch64-darwin" = {
      suffix = "darwin-arm64";
      hash = "sha256-ldaZ3S8Dgn6VKG/oVJmdQuPQv+7DeviMW/SZCO5WqlM=";
    };
  };

  inherit (stdenv.hostPlatform) system;
  source =
    sources.${system}
      or (throw "claude-code: unsupported platform ${system}");
in
stdenv.mkDerivation rec {
  pname = "claude-code";
  version = "2.1.170";

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
