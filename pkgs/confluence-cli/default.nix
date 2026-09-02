{ lib, buildNpmPackage, fetchurl }:

buildNpmPackage rec {
  pname = "confluence-cli";
  version = "2.22.0";

  src = fetchurl {
    url = "https://registry.npmjs.org/confluence-cli/-/confluence-cli-${version}.tgz";
    hash = "sha256-m66/Ic0YFQOhevS+S/X9x1bFvAq6ZLlAOrME2sb6Ld0=";
  };

  sourceRoot = "package";

  postPatch = ''
    cp ${./package-lock.json} package-lock.json

    # Remove devDependencies so npm doesn't try to fetch them in the sandbox
    sed -i '/"devDependencies"/,/}/d' package.json
  '';

  npmDepsHash = "sha256-f373eifbKelQMHYAjbth9HkFlBX6VR3xew/IhtrKLIA=";
  npmFlags = [ "--omit=dev" ];

  dontNpmBuild = true;

  meta = {
    description = "CLI for Atlassian Confluence — read, create, update, and search pages";
    homepage = "https://github.com/pchuri/confluence-cli";
    license = lib.licenses.mit;
    mainProgram = "confluence";
  };
}
