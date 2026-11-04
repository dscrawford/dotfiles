{ writeShellApplication, nodejs }:

writeShellApplication {
  name = "scooter-acp";
  runtimeInputs = [ nodejs ];
  text = ''
    exec node ${./src}/main.mjs "$@"
  '';
}
