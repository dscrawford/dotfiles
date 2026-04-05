{ lib, buildNpmPackage, fetchurl, nodejs, vips, pkg-config, python3 }:

buildNpmPackage rec {
  pname = "ruflo";
  version = "3.5.51";

  src = fetchurl {
    url = "https://registry.npmjs.org/ruflo/-/ruflo-${version}.tgz";
    hash = "sha256-BTr0ukt1wOyAXEylij70jTrGMn7bCUyj7GJ69onjE3Y=";
  };

  sourceRoot = "package";

  postPatch = ''
    cp ${./package-lock.json} package-lock.json
  '';

  npmDepsHash = "sha256-zslkeuwFr8MuJVhQ7yfi4U3N+ymdSUszViY1qua6HNE=";
  npmFlags = [ "--legacy-peer-deps" ];
  makeCacheWritable = true;

  nativeBuildInputs = [ pkg-config python3 ];
  buildInputs = [ vips ];

  dontNpmBuild = true;

  meta = {
    description = "Enterprise AI agent orchestration platform for Claude Code";
    homepage = "https://github.com/ruvnet/ruflo";
    license = lib.licenses.mit;
    mainProgram = "ruflo";
  };
}
