{ lib, writeShellScriptBin, nodejs }:

# slack-cli is a legacy npm package (2016) with native deps that don't build
# on modern Node.js. Use npx to run it on-demand instead.
writeShellScriptBin "slackcli" ''
  exec ${nodejs}/bin/npx --yes slack-cli@1.0.18 "$@"
''
