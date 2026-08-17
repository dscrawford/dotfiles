# shared/home/ollama.nix
# One declaration covers both platforms: home-manager renders it as a systemd
# user service on Linux and a launchd agent on macOS (Metal needs no flag).
# Backs the local-llm-router MCP server (pkgs/local-llm-mcp); also puts the
# ollama CLI on PATH. The desktop overrides package to ollama-cuda in flake.nix.
{ ... }:

{
  services.ollama = {
    enable = true;
    # Explicit loopback pin so an upstream default change can't widen the
    # unauthenticated API beyond localhost.
    host = "127.0.0.1";
    port = 11434;
  };
}
