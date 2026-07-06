{ lib, buildNpmPackage, fetchurl, vips, pkg-config, python3 }:

buildNpmPackage rec {
  pname = "ruflo";
  version = "3.16.3";

  src = fetchurl {
    url = "https://registry.npmjs.org/ruflo/-/ruflo-${version}.tgz";
    hash = "sha256-yOKYoDNozsVS6E4YuQ5tVCgcDXKD2EJNyyS9KJ10iMg=";
  };

  sourceRoot = "package";

  postPatch = ''
    cp ${./package-lock.json} package-lock.json
  '';

  npmDepsHash = "sha256-hqDCgqC3xTMsxmsj18YlQUMkNYSggOm5xgiZGbHzdrE=";
  makeCacheWritable = true;

  # onnxruntime-node (pulled in transitively via agentic-flow) runs a
  # postinstall that downloads extra execution-provider binaries from
  # api.nuget.org, which fails in the offline build sandbox. The base CPU
  # runtime is already bundled in the npm package, so skip the download.
  ONNXRUNTIME_NODE_INSTALL = "skip";

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
