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

  # Redirect @xenova/transformers ONNX model cache out of the read-only nix store.
  # env.js is an ES module so require() is not available; use process.env instead.
  # Tested against @xenova/transformers 2.17.2.
  postInstall = ''
    substituteInPlace $out/lib/node_modules/ruflo/node_modules/@xenova/transformers/src/env.js \
      --replace-fail \
        "path.join(__dirname, '/.cache/')" \
        "(process.env.XDG_CACHE_HOME || (process.env.HOME + '/.cache')) + '/ruflo/transformers'"
  '';

  meta = {
    description = "Enterprise AI agent orchestration platform for Claude Code";
    homepage = "https://github.com/ruvnet/ruflo";
    license = lib.licenses.mit;
    mainProgram = "ruflo";
  };
}
