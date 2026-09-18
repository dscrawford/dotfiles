{ writeShellApplication, nodejs, callPackage }:

let
  ruflo = callPackage ../ruflo { };
in
writeShellApplication {
  name = "ruflo-mcp";
  runtimeInputs = [ nodejs ruflo ];
  text = ''
    exec node ${./supervise.mjs} "$@"
  '';
}
