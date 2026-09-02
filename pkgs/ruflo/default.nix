{ lib, buildNpmPackage, fetchurl, autoPatchelfHook, stdenv }:

buildNpmPackage rec {
  pname = "ruflo";
  version = "3.38.21";

  src = fetchurl {
    url = "https://registry.npmjs.org/ruflo/-/ruflo-${version}.tgz";
    hash = "sha256-8ILK/cQanYWpPqJvugjX9BMc1qQTB2b6RczUCeEw7Ms=";
  };

  sourceRoot = "package";

  postPatch = ''
    cp ${./package-lock.json} package-lock.json
  '';

  npmDepsHash = "sha256-tztU4PsSJD38s/rRqgs+OgpIB7qzdcBCFWQ4kMp1saA=";
  makeCacheWritable = true;

  # onnxruntime-node (pulled in transitively via agentic-flow) runs a
  # postinstall that downloads extra execution-provider binaries from
  # api.nuget.org, which fails in the offline build sandbox. The base CPU
  # runtime is already bundled in the npm package, so skip the download.
  ONNXRUNTIME_NODE_INSTALL = "skip";
  # A second, older onnxruntime-node (1.21, nested under agentic-flow ->
  # @huggingface/transformers) predates the combined flag and only reads
  # the CUDA-specific one.
  ONNXRUNTIME_NODE_INSTALL_CUDA = "skip";

  # sharp >= 0.33 ships prebuilt @img/sharp-linux-x64 + bundled libvips, but
  # its install check prefers a pkg-config-visible global libvips and then
  # demands node-gyp as an npm dependency to build from source. Hide the
  # global one so the prebuilt path is taken.
  SHARP_IGNORE_GLOBAL_LIBVIPS = "1";

  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];
  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [ stdenv.cc.cc.lib ];

  dontNpmBuild = true;

  # Prebuilt musl variants ship next to the glibc ones and want
  # libc.musl-x86_64.so.1, which autoPatchelf cannot provide; they are dead
  # weight on glibc.
  preFixup = ''
    find $out -path '*/prebuilds/*' -name '*musl*.node' -delete
  '';

  meta = {
    description = "Enterprise AI agent orchestration platform for Claude Code";
    homepage = "https://github.com/ruvnet/ruflo";
    license = lib.licenses.mit;
    mainProgram = "ruflo";
    platforms = lib.platforms.unix;
  };
}
