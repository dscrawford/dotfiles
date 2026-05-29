{ lib, buildNpmPackage, fetchurl, vips, pkg-config, python3 }:

buildNpmPackage rec {
  pname = "ruflo";
  version = "3.10.5";

  src = fetchurl {
    url = "https://registry.npmjs.org/ruflo/-/ruflo-${version}.tgz";
    hash = "sha256-mERb/RxQEuuN7aC6xJg0Qfi5GDU8P1SvkdfA1CiggbU=";
  };

  sourceRoot = "package";

  postPatch = ''
    cp ${./package-lock.json} package-lock.json
  '';

  npmDepsHash = "sha256-BMK4d8xHqVpT/ElwQduxL5qx2IKADEbBwi4BFmiTg3c=";
  makeCacheWritable = true;

  nativeBuildInputs = [ pkg-config python3 ];
  buildInputs = [ vips ];

  dontNpmBuild = true;

  meta = {
    description = "Enterprise AI agent orchestration platform for Claude Code";
    homepage = "https://github.com/ruvnet/ruflo";
    license = lib.licenses.mit;
    mainProgram = "ruflo";
    platforms = lib.platforms.unix;
  };
}
