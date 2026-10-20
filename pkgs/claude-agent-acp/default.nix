{ lib, buildNpmPackage, fetchurl, autoPatchelfHook, stdenv }:

buildNpmPackage rec {
  pname = "claude-agent-acp";
  version = "0.94.0";

  src = fetchurl {
    url = "https://registry.npmjs.org/@agentclientprotocol/claude-agent-acp/-/claude-agent-acp-${version}.tgz";
    hash = "sha256-oWIpj/sXsqPU8NB9A14nK52ODdqTmqR6u8ymHIfOJqk=";
  };

  sourceRoot = "package";

  postPatch = ''
    cp ${./package-lock.json} package-lock.json
  '';

  npmDepsHash = "sha256-Z0uaeXlkmNTw21rHleaPP6H7x7cq9KS7HljzBG0VnyA=";

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
