{ lib, stdenv, fetchurl, bubblewrap, procps, socat, makeBinaryWrapper, autoPatchelfHook }:

let
  # Anthropic ships a per-platform prebuilt native binary as a separate npm
  # package: @anthropic-ai/claude-code-<suffix>. Map each Nix system to its
  # tarball suffix + hash.
  sources = {
    "x86_64-linux" = {
      suffix = "linux-x64";
      hash = "sha256-A3+KIa50opthPwLNOYbO+wsA/LFPlXqNq5jcLj8/11M=";
    };
    "aarch64-linux" = {
      suffix = "linux-arm64";
      hash = "sha256-LwrVDNPv1XBzI/SLQ68ixcvARedM38FtJcWnNYHzsZY=";
    };
    "x86_64-darwin" = {
      suffix = "darwin-x64";
      hash = "sha256-oDvc2cfeKf6fAb7QuM/z9aYa2pIAU2KW4rF/Vl0ClMI=";
    };
    "aarch64-darwin" = {
      suffix = "darwin-arm64";
      hash = "sha256-66N00nlu327ZZStA1MCBobfSwga18q7GGH/LM4QIdoY=";
    };
  };

  inherit (stdenv.hostPlatform) system;
  source =
    sources.${system}
      or (throw "claude-code: unsupported platform ${system}");
in
stdenv.mkDerivation rec {
  pname = "claude-code";
  version = "2.1.258";

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
