{ lib, buildNpmPackage, fetchurl }:

buildNpmPackage rec {
  pname = "claude-agent-acp";
  version = "0.39.0";

  src = fetchurl {
    url = "https://registry.npmjs.org/@agentclientprotocol/claude-agent-acp/-/claude-agent-acp-${version}.tgz";
    hash = "sha256-L0PO3myte4oBsnyn3uaSVVwnVvyVvorxa1DcYLknX3U=";
  };

  sourceRoot = "package";

  postPatch = ''
    cp ${./package-lock.json} package-lock.json
  '';

  npmDepsHash = "sha256-vah4q9PzzHnGuvgyUhRSSrJYVwo3AT+J7BOxlq95IeE=";

  dontNpmBuild = true;

  meta = {
    description = "ACP-compatible Claude coding agent";
    homepage = "https://github.com/agentclientprotocol/claude-agent-acp";
    license = lib.licenses.mit;
    mainProgram = "claude-agent-acp";
  };
}
