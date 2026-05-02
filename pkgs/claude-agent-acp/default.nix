{ lib, buildNpmPackage, fetchurl }:

buildNpmPackage rec {
  pname = "claude-agent-acp";
  version = "0.23.1";

  src = fetchurl {
    url = "https://registry.npmjs.org/@zed-industries/claude-agent-acp/-/claude-agent-acp-${version}.tgz";
    hash = "sha256-s4cKDvYAIzYK3c78URIlvsuGXvoIXyd4ssV0iJeJ4Mw=";
  };

  sourceRoot = "package";

  postPatch = ''
    cp ${./package-lock.json} package-lock.json
  '';

  npmDepsHash = "sha256-fzhaRMcwLQJplhHxd7vWiTRIo+UVg7QLWOqipw+FNJY=";

  dontNpmBuild = true;

  meta = {
    description = "ACP-compatible Claude coding agent";
    homepage = "https://github.com/AcpCoding/claude-agent-acp";
    license = lib.licenses.mit;
    mainProgram = "claude-agent-acp";
  };
}
