{ writeShellApplication, nodejs }:

writeShellApplication {
  name = "local-llm-mcp";
  runtimeInputs = [ nodejs ];
  text = ''
    exec node ${./server.mjs} "$@"
  '';
}
