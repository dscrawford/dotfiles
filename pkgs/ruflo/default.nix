{ lib, buildNpmPackage, fetchurl, autoPatchelfHook, stdenv, nodejs_22 }:

buildNpmPackage rec {
  pname = "ruflo";
  version = "3.42.5";

  src = fetchurl {
    url = "https://registry.npmjs.org/ruflo/-/ruflo-${version}.tgz";
    hash = "sha256-snSnkKkIsOP/gLeoqROEk5zwwdHlj51pVqdOjJKUHAc=";
  };

  sourceRoot = "package";

  # Node 24.19 backported cleanup hooks into the header-only
  # node::ObjectWrap, so ~ObjectWrap() calls RemoveEnvironmentCleanupHook()
  # with no entered context and node aborts on `(env) != nullptr`.
  # better-sqlite3 12.x still derives from ObjectWrap, so every GC that
  # finalizes a Statement kills the MCP server mid-session (~50 memory tool
  # calls in), taking the stdio transport with it. Node 22 predates the
  # backport; upstream's own fix is better-sqlite3 13.x (N-API), which is
  # outside the `^12.9.0` optional-dependency range ruflo pins.
  nodejs = nodejs_22;

  postPatch = ''
    cp ${./package-lock.json} package-lock.json
  '';

  npmDepsHash = "sha256-K9DUfdeKhS9BKCM0ebfZ6X78k0X6R0+dAQW3dK1CBZM=";
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
