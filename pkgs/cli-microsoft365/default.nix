{ lib, buildNpmPackage, fetchurl }:

buildNpmPackage rec {
  pname = "cli-microsoft365";
  version = "11.8.0";

  src = fetchurl {
    url = "https://registry.npmjs.org/@pnp/cli-microsoft365/-/cli-microsoft365-${version}.tgz";
    hash = "sha256-xNgK9+0K0xfhTdyQ9NopYiuxOozhXbYkYyCsMmIzFVI=";
  };

  sourceRoot = "package";

  postPatch = ''
    cp ${./package-lock.json} package-lock.json
  '';

  npmDepsHash = "sha256-pVS6/MLJyEcV+hBoZIqLwy16L/3EjDgZdvf6e1LHrGk=";

  dontNpmBuild = true;

  meta = {
    description = "CLI for Microsoft 365 — manage Outlook, Teams, SharePoint, OneDrive and more";
    homepage = "https://pnp.github.io/cli-microsoft365/";
    license = lib.licenses.mit;
    mainProgram = "m365";
  };
}
