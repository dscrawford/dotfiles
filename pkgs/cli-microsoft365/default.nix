{ lib, buildNpmPackage, fetchurl }:

buildNpmPackage rec {
  pname = "cli-microsoft365";
  version = "11.6.0";

  src = fetchurl {
    url = "https://registry.npmjs.org/@pnp/cli-microsoft365/-/cli-microsoft365-${version}.tgz";
    hash = "sha256-QQGCKjomQxDKlBAxS5RV78KQ/648wSaGx12LoAqVLOg=";
  };

  sourceRoot = "package";

  postPatch = ''
    cp ${./package-lock.json} package-lock.json
  '';

  npmDepsHash = "sha256-Xr0RaEHZ1qsq98nbifMfEeHYccTCtOAZKxuK7bidITc=";

  dontNpmBuild = true;

  meta = {
    description = "CLI for Microsoft 365 — manage Outlook, Teams, SharePoint, OneDrive and more";
    homepage = "https://pnp.github.io/cli-microsoft365/";
    license = lib.licenses.mit;
    mainProgram = "m365";
  };
}
