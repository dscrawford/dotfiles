{ lib, buildNpmPackage, fetchurl }:

buildNpmPackage rec {
  pname = "confluence-cli";
  version = "2.23.0";

  src = fetchurl {
    url = "https://registry.npmjs.org/confluence-cli/-/confluence-cli-${version}.tgz";
    hash = "sha256-ALFqwlnr0XlxNK2eYo2sJpZW/UVYjTn3m7rG1gS41hU=";
  };

  sourceRoot = "package";

  postPatch = ''
    cp ${./package-lock.json} package-lock.json

    # Remove devDependencies so npm doesn't try to fetch them in the sandbox
    sed -i '/"devDependencies"/,/}/d' package.json
  '';

  npmDepsHash = "sha256-HonfO07S7tswyYSVHdz/an5YvZV5DYRmKlKvF52E9BU=";
  npmFlags = [ "--omit=dev" ];

  dontNpmBuild = true;

  meta = {
    description = "CLI for Atlassian Confluence — read, create, update, and search pages";
    homepage = "https://github.com/pchuri/confluence-cli";
    license = lib.licenses.mit;
    mainProgram = "confluence";
  };
}
