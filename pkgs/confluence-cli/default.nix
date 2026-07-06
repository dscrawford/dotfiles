{ lib, buildNpmPackage, fetchurl }:

buildNpmPackage rec {
  pname = "confluence-cli";
  version = "2.15.0";

  src = fetchurl {
    url = "https://registry.npmjs.org/confluence-cli/-/confluence-cli-${version}.tgz";
    hash = "sha256-ysGg+zwW++XHMGrTZxyA8IX50t4wKmLsww0+SZFDyXM=";
  };

  sourceRoot = "package";

  postPatch = ''
    cp ${./package-lock.json} package-lock.json

    # Remove devDependencies so npm doesn't try to fetch them in the sandbox
    sed -i '/"devDependencies"/,/}/d' package.json
  '';

  npmDepsHash = "sha256-S3liH4UGkE5zftEPioZiS+R931g4rTYywkPBth/VLfc=";
  npmFlags = [ "--omit=dev" ];

  dontNpmBuild = true;

  meta = {
    description = "CLI for Atlassian Confluence — read, create, update, and search pages";
    homepage = "https://github.com/pchuri/confluence-cli";
    license = lib.licenses.mit;
    mainProgram = "confluence";
  };
}
