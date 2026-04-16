{ lib, buildNpmPackage, fetchurl }:

buildNpmPackage rec {
  pname = "confluence-cli";
  version = "1.30.1";

  src = fetchurl {
    url = "https://registry.npmjs.org/confluence-cli/-/confluence-cli-${version}.tgz";
    hash = "sha256-kUwvwuQ6HEwFoXHExWUlcNvgWB78XPPhV6dmUv8SqQg=";
  };

  sourceRoot = "package";

  postPatch = ''
    cp ${./package-lock.json} package-lock.json
  '';

  npmDepsHash = "sha256-40Id6atb3HrXX4tN/VqtL37rdYrOJP1zNYEKDe6PeEY=";

  dontNpmBuild = true;

  meta = {
    description = "CLI for Atlassian Confluence — read, create, update, and search pages";
    homepage = "https://github.com/pchuri/confluence-cli";
    license = lib.licenses.mit;
    mainProgram = "confluence";
  };
}
