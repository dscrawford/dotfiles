{ lib, buildNpmPackage, fetchurl, autoPatchelfHook, stdenv }:

buildNpmPackage rec {
  pname = "claude-agent-acp";
  version = "0.73.0";

  src = fetchurl {
    url = "https://registry.npmjs.org/@agentclientprotocol/claude-agent-acp/-/claude-agent-acp-${version}.tgz";
    hash = "sha256-6wPQxsGTRyZTXVxrje/Ts3wsLXf12dA306l9Yk6nM8M=";
  };

  sourceRoot = "package";

  postPatch = ''
    cp ${./package-lock.json} package-lock.json
  '';

  npmDepsHash = "sha256-IK/5NrSXWHlF0NQIt/vq9KjngROOepytaN7i8DOxSwA=";

  # autoPatchelfHook + libstdc++ are only needed to fix up ELF binaries from
  # native npm deps on Linux; Darwin needs neither.
  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];
  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [ stdenv.cc.cc.lib ];

  dontNpmBuild = true;

  meta = {
    description = "ACP-compatible Claude coding agent";
    homepage = "https://github.com/agentclientprotocol/claude-agent-acp";
    license = lib.licenses.asl20;
    mainProgram = "claude-agent-acp";
    platforms = lib.platforms.unix;
  };
}
