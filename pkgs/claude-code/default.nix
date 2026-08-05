{ lib, stdenv, fetchurl, bubblewrap, procps, socat, makeBinaryWrapper, autoPatchelfHook }:

let
  # Anthropic ships a per-platform prebuilt native binary as a separate npm
  # package: @anthropic-ai/claude-code-<suffix>. Map each Nix system to its
  # tarball suffix + hash.
  sources = {
    "x86_64-linux" = {
      suffix = "linux-x64";
      hash = "sha256-VkfafvwHPjJJ0vmIufcG9Xbr8kDxnVD9yjXwBwlUNFo=";
    };
    "aarch64-linux" = {
      suffix = "linux-arm64";
      hash = "sha256-1wENBrrhC+LcpwNjPHMNUsXBORFl6OzNSf9ufCVxwkQ=";
    };
    "x86_64-darwin" = {
      suffix = "darwin-x64";
      hash = "sha256-P6/6Rx4btBjtHxhS2EpE+WyuYc7ktKPRDpzsYkRw0Xw=";
    };
    "aarch64-darwin" = {
      suffix = "darwin-arm64";
      hash = "sha256-y5rk5jGM9zgT5BGe1s7fwP0p9CH8ldGDzCk/FI2Z92o=";
    };
  };

  inherit (stdenv.hostPlatform) system;
  source =
    sources.${system}
      or (throw "claude-code: unsupported platform ${system}");
in
stdenv.mkDerivation rec {
  pname = "claude-code";
  version = "2.1.200";

  src = fetchurl {
    url = "https://registry.npmjs.org/@anthropic-ai/claude-code-${source.suffix}/-/claude-code-${source.suffix}-${version}.tgz";
    inherit (source) hash;
  };

  sourceRoot = "package";

  nativeBuildInputs =
    [ makeBinaryWrapper ]
    ++ lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];

  dontBuild = true;
  dontConfigure = true;
  # The Linux binary is Bun-compiled with its JS payload appended after the ELF.
  # Stripping or `patchelf --set-rpath` relocates and corrupts that payload;
  # autoPatchelfHook + dontStrip leave it intact. Darwin needs neither.
  dontStrip = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 claude $out/lib/claude-code/claude

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
