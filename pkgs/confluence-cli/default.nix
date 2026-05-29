{ lib, buildNpmPackage, fetchurl }:

buildNpmPackage rec {
  pname = "confluence-cli";
  version = "2.10.0";

  src = fetchurl {
    url = "https://registry.npmjs.org/confluence-cli/-/confluence-cli-${version}.tgz";
    hash = "sha256-DHiZT+F+kYlXotbIHjL5cWZ7/IyuO8pazB5SRAXqL9o=";
  };

  sourceRoot = "package";

  postPatch = ''
    cp ${./package-lock.json} package-lock.json

    # Remove devDependencies so npm doesn't try to fetch them in the sandbox
    sed -i '/"devDependencies"/,/}/d' package.json
  '';

  npmDepsHash = "sha256-jXstuaq8erZl4nY7dAKL2t5odlGydWF0pcMCPy0J27M=";
  npmFlags = [ "--omit=dev" ];

  dontNpmBuild = true;

  meta = {
    description = "CLI for Atlassian Confluence — read, create, update, and search pages";
    homepage = "https://github.com/pchuri/confluence-cli";
    license = lib.licenses.mit;
    mainProgram = "confluence";
  };
}
