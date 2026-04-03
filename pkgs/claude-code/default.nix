{ lib, stdenv, buildNpmPackage, fetchurl, bubblewrap, procps, socat }:

buildNpmPackage rec {
  pname = "claude-code";
  version = "2.1.91";

  src = fetchurl {
    url = "https://registry.npmjs.org/@anthropic-ai/claude-code/-/claude-code-${version}.tgz";
    hash = "sha256-T7Ta53HW+tHnRwN0EUj17i0kg39KBOqycEF0b3pbPis=";
  };

  sourceRoot = "package";

  postPatch = ''
    cp ${./package-lock.json} package-lock.json

    # https://github.com/anthropics/claude-code/issues/15195
    substituteInPlace cli.js \
      --replace-fail '#!/bin/sh' '#!/usr/bin/env sh'
  '';

  npmDepsHash = "sha256-0ppKP+XMgTzVVZtL7GDsOjgvSPUDrUa7SoG048RLaNg=";

  dontNpmBuild = true;

  env.AUTHORIZED = "1";

  postInstall = ''
    wrapProgram $out/bin/claude \
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
  '';

  meta = {
    description = "Agentic coding tool that lives in your terminal";
    homepage = "https://github.com/anthropics/claude-code";
    license = lib.licenses.unfree;
    mainProgram = "claude";
  };
}
