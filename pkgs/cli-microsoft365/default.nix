{ lib, buildNpmPackage, fetchurl }:

buildNpmPackage rec {
  pname = "cli-microsoft365";
  version = "11.11.0";

  src = fetchurl {
    url = "https://registry.npmjs.org/@pnp/cli-microsoft365/-/cli-microsoft365-${version}.tgz";
    hash = "sha256-RdtTd3szeKVXSqNqLRRMuHKsyoPFYJt4q1mBBR59LRc=";
  };

  sourceRoot = "package";

  # The tarball ships an npm-shrinkwrap.json that takes precedence over any
  # package-lock and has entries with no `resolved`, so the deps fetcher skips
  # them and npm ci then fails offline. Drop it in favour of a full lock.
  postPatch = ''
    rm -f npm-shrinkwrap.json
    cp ${./package-lock.json} package-lock.json
  '';

  npmDepsHash = "sha256-B5493iUGpEkR3EQEBRVjTrjpnOzuVKgU/6PwiSBpsfc=";

  dontNpmBuild = true;

  meta = {
    description = "CLI for Microsoft 365 — manage Outlook, Teams, SharePoint, OneDrive and more";
    homepage = "https://pnp.github.io/cli-microsoft365/";
    license = lib.licenses.mit;
    mainProgram = "m365";
  };
}
