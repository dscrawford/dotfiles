{ lib, buildNpmPackage, fetchurl }:

buildNpmPackage rec {
  pname = "claude-agent-acp";
  version = "0.22.0";

  src = fetchurl {
    url = "https://registry.npmjs.org/@zed-industries/claude-agent-acp/-/claude-agent-acp-${version}.tgz";
    hash = "sha256-Yc/kfXLlBYbHll1JY+vs7UdvbZJPqEgTgjSTaDzvIC4=";
  };

  sourceRoot = "package";

  postPatch = ''
    cp ${./package-lock.json} package-lock.json
  '';

  npmDepsHash = "sha256-veyeionYrED07a5Hi7tQiyh4wCISE9fPdKIO0mZFnaQ=";

  dontNpmBuild = true;

  meta = {
    description = "ACP-compatible Claude coding agent";
    homepage = "https://github.com/AcpCoding/claude-agent-acp";
    license = lib.licenses.mit;
    mainProgram = "claude-agent-acp";
  };
}
