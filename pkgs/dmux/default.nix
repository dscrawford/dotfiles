{ lib, buildNpmPackage, fetchurl }:

buildNpmPackage rec {
  pname = "dmux";
  version = "5.10.0";

  src = fetchurl {
    url = "https://registry.npmjs.org/dmux/-/dmux-${version}.tgz";
    hash = "sha256-meJvjTlzA7Ym/Pj6JkfqJXJQa5iWAVrKk+19bGs+xzM=";
  };

  sourceRoot = "package";

  postPatch = ''
    cp ${./package-lock.json} package-lock.json

    # Remove devDependencies so npm doesn't try to fetch them in the sandbox
    sed -i '/"devDependencies"/,/^  }/d' package.json

    # prepack builds a macOS helper bundle via pnpm, which isn't in the
    # sandbox; the published tarball already ships dist/, so drop it
    sed -i '/"prepack":/d' package.json
  '';

  npmDepsHash = "sha256-soLGnTOqAqbOLGqrJVrEEEr+diMd57qBYYLC+Ikk45I=";
  npmFlags = [ "--omit=dev" ];

  dontNpmBuild = true;

  meta = {
    description = "Tmux pane manager with AI agent integration for parallel development workflows";
    homepage = "https://github.com/standardagents/dmux";
    license = lib.licenses.mit;
    mainProgram = "dmux";
  };
}
