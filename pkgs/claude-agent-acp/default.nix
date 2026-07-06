{ lib, buildNpmPackage, fetchurl, autoPatchelfHook, stdenv }:

buildNpmPackage rec {
  pname = "claude-agent-acp";
  version = "0.55.0";

  src = fetchurl {
    url = "https://registry.npmjs.org/@agentclientprotocol/claude-agent-acp/-/claude-agent-acp-${version}.tgz";
    hash = "sha256-757QMieWw4j3goQ7h/PMzxhl8WYNeOy04wv/+Dqfogc=";
  };

  sourceRoot = "package";

  postPatch = ''
    cp ${./package-lock.json} package-lock.json
  '';

  npmDepsHash = "sha256-ih4sjFPD/cqcEPsG9DJjYpb2Z1CexJDBNW7DEXbOCOo=";

  # autoPatchelfHook + libstdc++ are only needed to fix up ELF binaries from
  # native npm deps on Linux; Darwin needs neither.
  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];
  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [ stdenv.cc.cc.lib ];

  dontNpmBuild = true;

  meta = {
    description = "ACP-compatible Claude coding agent";
    homepage = "https://github.com/agentclientprotocol/claude-agent-acp";
    license = lib.licenses.mit;
    mainProgram = "claude-agent-acp";
    platforms = lib.platforms.unix;
  };
}
