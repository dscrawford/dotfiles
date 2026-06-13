{ lib, buildNpmPackage, fetchurl, vips, pkg-config, python3 }:

buildNpmPackage rec {
  pname = "ruflo";
  version = "3.10.40";

  src = fetchurl {
    url = "https://registry.npmjs.org/ruflo/-/ruflo-${version}.tgz";
    hash = "sha256-CgQdnn/HY1ON7hfyVbOZNXB/J32EQ+Vg3qpYW7eOMBA=";
  };

  sourceRoot = "package";

  postPatch = ''
    cp ${./package-lock.json} package-lock.json
  '';

  npmDepsHash = "sha256-lXlOX69NkHMxo9pGx/OkLPLGAdplA9ORL5/653mYDj8=";
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
